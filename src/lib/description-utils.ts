/**
 * Search for a book description on Google Books.
 * Tries ISBN first (most precise), then title + author.
 */
export async function searchDescription(
  title: string, authors: string[], isbn?: string
): Promise<string | null> {
  const apiKey = process.env.GOOGLE_BOOKS_API_KEY ?? "";
  const keyParam = apiKey ? `&key=${apiKey}` : "";

  // Try ISBN first
  if (isbn) {
    try {
      const res = await fetch(
        `https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}&maxResults=1${keyParam}`,
        { signal: AbortSignal.timeout(4000) }
      );
      if (res.ok) {
        const data = await res.json();
        const desc = data.items?.[0]?.volumeInfo?.description;
        if (desc && desc.length > 20) return desc;
      }
    } catch { /* continue */ }
  }

  // Fallback: title + author
  const author = authors[0] ?? "";
  const q = author ? `intitle:${title} inauthor:${author}` : `intitle:${title}`;
  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=${encodeURIComponent(q)}&langRestrict=fr&maxResults=5${keyParam}`,
      { signal: AbortSignal.timeout(4000) }
    );
    if (!res.ok) return null;
    const data = await res.json();
    if (!data.items?.length) return null;

    const titleLower = title.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    const titleWords = titleLower.split(/\s+/).filter(w => w.length >= 3);

    for (const item of data.items) {
      const vol = item.volumeInfo;
      if (!vol?.description || vol.description.length < 20) continue;
      const volTitle = (vol.title ?? "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
      const matchCount = titleWords.filter(w => volTitle.includes(w)).length;
      if (titleWords.length === 0 || matchCount >= titleWords.length * 0.5) {
        return vol.description;
      }
    }
    return null;
  } catch { return null; }
}
