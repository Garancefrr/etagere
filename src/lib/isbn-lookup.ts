import { LookupResult, BookType } from "@/types";

function detectBookType(data: {
  subjects?: string[];
  genres?: string[];
  categories?: string[];
  title?: string;
}): BookType {
  const terms = [
    ...(data.subjects || []),
    ...(data.genres || []),
    ...(data.categories || []),
    data.title || "",
  ].join(" ").toLowerCase();

  if (/manga|manhwa|manhwa|webtoon|shonen|shojo|seinen|josei/.test(terms)) return "manga";
  if (/bande dessinée|comic|bd|graphic novel|comics|fumetti|tebeo/.test(terms)) return "bd";
  return "livre";
}

export async function lookupISBN(isbn: string): Promise<LookupResult | null> {
  const clean = isbn.replace(/[-\s]/g, "");

  // ── Open Library ──
  try {
    const res = await fetch(
      `https://openlibrary.org/api/books?bibkeys=ISBN:${clean}&format=json&jscmd=data`,
      { next: { revalidate: 86400 } }
    );
    const data = await res.json();
    const key = `ISBN:${clean}`;

    if (data[key]) {
      const b = data[key];
      const authors = b.authors?.map((a: { name: string }) => a.name) ?? [];
      const cover = b.cover?.large || b.cover?.medium || b.cover?.small;

      // Series detection via subjects / notes
      let series_name: string | undefined;
      let series_index: number | undefined;

      const subjects: string[] = b.subjects?.map((s: { name?: string } | string) =>
        typeof s === "string" ? s : s.name || ""
      ) ?? [];

      // Check for series in notes or series_statement
      if (b.series) {
        const s = Array.isArray(b.series) ? b.series[0] : b.series;
        if (typeof s === "string") {
          series_name = s.replace(/\s*#?\d+.*$/, "").trim();
          const numMatch = s.match(/#?(\d+)/);
          if (numMatch) series_index = parseInt(numMatch[1]);
        }
      }

      return {
        isbn: clean,
        title: b.title,
        authors,
        cover_url: cover,
        publisher: b.publishers?.[0]?.name,
        published_year: b.publish_date ? parseInt(b.publish_date.slice(-4)) : undefined,
        page_count: b.number_of_pages,
        description: b.excerpts?.[0]?.text,
        series_name,
        series_index,
        book_type: detectBookType({ subjects, title: b.title }),
      };
    }
  } catch (e) {
    console.error("Open Library error:", e);
  }

  // ── Google Books ──
  try {
    const res = await fetch(
      `https://www.googleapis.com/books/v1/volumes?q=isbn:${clean}`,
      { next: { revalidate: 86400 } }
    );
    const data = await res.json();

    if (data.items?.[0]) {
      const vol = data.items[0].volumeInfo;
      const categories: string[] = vol.categories ?? [];

      // Google Books often has series info in title or subtitle
      let series_name: string | undefined;
      let series_index: number | undefined;

      // Pattern: "Title, Vol. 3" or "Series Name #5" or "Title (Series Name, 2)"
      const fullTitle = `${vol.title || ""} ${vol.subtitle || ""}`;
      const volMatch = fullTitle.match(/(?:vol(?:ume)?\.?\s*|tome\s*|t\.\s*|#\s*)(\d+)/i);
      if (volMatch) {
        series_index = parseInt(volMatch[1]);
        // Series name = title without the volume part
        series_name = vol.title
          .replace(/[,\s]*(?:vol(?:ume)?\.?\s*|tome\s*|t\.\s*|#\s*)\d+.*/i, "")
          .trim() || undefined;
      }

      // Also check seriesInfo if present (newer Google Books API)
      if (vol.seriesInfo?.bookDisplayNumber) {
        series_index = parseInt(vol.seriesInfo.bookDisplayNumber);
        series_name = vol.seriesInfo.shortSeriesBookTitle || series_name;
      }

      return {
        isbn: clean,
        title: vol.title,
        authors: vol.authors ?? [],
        cover_url: vol.imageLinks?.thumbnail?.replace("http:", "https:"),
        publisher: vol.publisher,
        published_year: vol.publishedDate ? parseInt(vol.publishedDate.slice(0, 4)) : undefined,
        page_count: vol.pageCount,
        description: vol.description,
        series_name,
        series_index,
        book_type: detectBookType({ categories, title: vol.title }),
      };
    }
  } catch (e) {
    console.error("Google Books error:", e);
  }

  return null;
}
