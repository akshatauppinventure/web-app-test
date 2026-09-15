import Link from "next/link";

// Landing page. Sign-in buttons become real in T07 (Auth.js BFF); until then they are placeholders.
export default function HomePage() {
  return (
    <>
      <h1>web-app-test</h1>
      <p>A hello-world application on a security-first two-VPS deployment.</p>
      <div className="buttons">
        <button type="button" disabled aria-disabled="true">
          Sign in with Google (available in T07)
        </button>
        <Link className="button" href="/hello">
          Go to /hello
        </Link>
      </div>
    </>
  );
}
