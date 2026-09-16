import { signInWithApple, signInWithGoogle, signInWithKeycloak } from "@/app/actions";

// Apple stays hidden until the Apple Developer Program + domain exist (ADR-0010 §4).
const appleEnabled = process.env.NEXT_PUBLIC_APPLE_LOGIN === "true";

export function SignInButtons() {
  return (
    <div className="buttons">
      <form action={signInWithGoogle}>
        <button type="submit">Sign in with Google</button>
      </form>
      {appleEnabled ? (
        <form action={signInWithApple}>
          <button type="submit">Sign in with Apple</button>
        </form>
      ) : null}
      <form action={signInWithKeycloak}>
        <button type="submit">Sign in with email</button>
      </form>
    </div>
  );
}
