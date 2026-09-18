"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import styles from "./login.module.css";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setErro(null);
    setCarregando(true);

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password: senha,
    });

    setCarregando(false);

    if (error) {
      setErro("E-mail ou senha inválidos.");
      return;
    }

    router.push("/");
    router.refresh();
  }

  return (
    <main className={styles.container}>
      <form className={styles.card} onSubmit={handleSubmit}>
        <h1 className={styles.titulo}>Compras Fácil</h1>
        <p className={styles.subtitulo}>Entre com sua conta para continuar</p>

        <label className={styles.campo}>
          <span>E-mail</span>
          <input
            type="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            required
            autoComplete="email"
          />
        </label>

        <label className={styles.campo}>
          <span>Senha</span>
          <input
            type="password"
            value={senha}
            onChange={(event) => setSenha(event.target.value)}
            required
            autoComplete="current-password"
          />
        </label>

        {erro && <p className={styles.erro}>{erro}</p>}

        <button type="submit" className={styles.botao} disabled={carregando}>
          {carregando ? "Entrando..." : "Entrar"}
        </button>
      </form>
    </main>
  );
}
