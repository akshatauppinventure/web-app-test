// Plain POST form: the /api/logout route checks the Origin header and performs the
// RP-initiated logout. No JavaScript and no client-side token handling involved.
export function SignOutButton() {
  return (
    <form action="/api/logout" method="post">
      <button type="submit">Sign out</button>
    </form>
  );
}
