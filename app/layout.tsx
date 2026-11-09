import type { Metadata } from "next";
import "./globals.css";
import "./cinema.css";
import "./cinema-reference.css";

const defaultUrl = process.env.VERCEL_URL
  ? `https://${process.env.VERCEL_URL}`
  : "http://localhost:3000";

export const metadata: Metadata = {
  metadataBase: new URL(defaultUrl),
  title: "XYZ Cinema · Trải nghiệm vượt xa điện ảnh",
  description: "Khám phá phim, chọn ghế và đặt vé tại XYZ Cinema.",
};


export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="vi">
      <body>
          {children}
      </body>
    </html>
  );
}
