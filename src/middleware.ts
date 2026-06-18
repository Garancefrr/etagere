export { default } from "next-auth/middleware";

export const config = {
  matcher: ["/library/:path*", "/collections/:path*", "/scan/:path*", "/stats/:path*", "/settings/:path*", "/import/:path*"],
};
