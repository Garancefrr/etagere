const PLACEHOLDER_PATTERNS = [
  "no_cover", "nocover", "image_not_available",
  "no-image", "default_cover", "notoile=1",
];

/**
 * Validates a cover URL — rejects known placeholder patterns.
 * Returns cleaned URL or null.
 */
export function validateCoverUrl(url: string | undefined | null): string | null {
  if (!url) return null;
  const clean = url
    .replace("http:", "https:")
    .replace("&edge=curl", "")
    .replace(/zoom=\d/, "zoom=3");
  if (PLACEHOLDER_PATTERNS.some(p => clean.toLowerCase().includes(p))) return null;
  return clean;
}

/**
 * Searches Google Books for a cover by title.
 * Tries multiple query variants for better match rate.
 */
export async function searchCoverByTitle(title: string, seriesName?: string): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  const queries = seriesName
    ? [`${seriesName} ${title}`, seriesName, title]
    : [title];

  for (const q of queries) {
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&langRestrict=fr&maxResults=5${keyParam}`,
        { signal: AbortSignal.timeout(5000) }
      );
      if (!res.ok) continue;
      const data = await res.json();
      if (!data.items?.length) continue;
      for (const item of data.items) {
        const vol = item.volumeInfo;
        if (!vol?.imageLinks) continue;
        let url = vol.imageLinks.extraLarge ?? vol.imageLinks.large ?? vol.imageLinks.medium ?? vol.imageLinks.thumbnail;
        if (!url) continue;
        const validated = validateCoverUrl(url);
        if (validated) return validated;
      }
    } catch { continue; }
  }
  return null;
}
