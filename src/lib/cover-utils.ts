/**
 * Validates and cleans a cover URL.
 * Returns null if the URL likely points to a placeholder/unavailable image.
 */
export async function validateCoverUrl(url: string | undefined | null): Promise<string | null> {
  if (!url) return null;

  // Clean the URL
  let clean = url
    .replace("http:", "https:")
    .replace("&edge=curl", "")
    .replace(/zoom=\d/, "zoom=1");

  // Known placeholder patterns to reject
  const PLACEHOLDER_PATTERNS = [
    "no_cover",
    "nocover",
    "image_not_available",
    "no-image",
    "default_cover",
    "notoile=1",  // BnF no-image flag
  ];

  if (PLACEHOLDER_PATTERNS.some(p => clean.toLowerCase().includes(p))) return null;

  // For Google Books, try fetching to check if image is real
  if (clean.includes("books.google.com")) {
    try {
      const res = await fetch(clean, { method: "HEAD", signal: AbortSignal.timeout(3000) });
      // Google returns 200 even for "Image not available" but with small content-length
      const size = res.headers.get("content-length");
      if (size && parseInt(size) < 2000) return null; // too small = placeholder
      if (!res.ok) return null;
      return clean;
    } catch { return null; }
  }

  return clean;
}

/**
 * Searches Google Books for a cover by exact title.
 */
export async function searchCoverByTitle(title: string, seriesName?: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";
  const q = seriesName ? `${seriesName} ${title}` : title;

  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=intitle:${encodeURIComponent(`"${q}"`)}&langRestrict=fr&maxResults=5${keyParam}`,
      { signal: AbortSignal.timeout(5000) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.items?.length) return null;

    const titleLower = title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const titleWords = titleLower.split(/\s+/).filter(w => w.length >= 3);

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.imageLinks) continue;
      const volTitle = (vol.title ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      if (titleWords.filter(w => volTitle.includes(w)).length < titleWords.length * 0.6) continue;

      let url = vol.imageLinks.large ?? vol.imageLinks.medium ?? vol.imageLinks.thumbnail;
      if (!url) continue;
      url = url.replace("http:", "https:").replace("&edge=curl", "").replace(/zoom=\d/, "zoom=3");

      const validated = await validateCoverUrl(url);
      if (validated) return validated;
    }
    return null;
  } catch { return null; }
}
