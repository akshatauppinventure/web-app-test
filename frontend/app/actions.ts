"use server";

import { signIn } from "@/auth";

// kc_idp_hint skips Keycloak's provider chooser and goes straight to Google (ADR-0011 §1).
export async function signInWithGoogle(): Promise<void> {
  await signIn("keycloak", { redirectTo: "/hello" }, { kc_idp_hint: "google" });
}

export async function signInWithKeycloak(): Promise<void> {
  await signIn("keycloak", { redirectTo: "/hello" });
}

export async function signInWithApple(): Promise<void> {
  await signIn("keycloak", { redirectTo: "/hello" }, { kc_idp_hint: "apple" });
}
