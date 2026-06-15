export { default } from "next-auth/middleware";

export const config = {
  matcher: ["/library", "/collections", "/scan", "/stats", "/settings"],
};
