export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api" || url.pathname.startsWith("/api/")) {
      const destino = new URL(
        url.pathname + url.search,
        "https://dvanille-api.onrender.com"
      );

      const requisicao = new Request(destino.toString(), request);
      const resposta = await fetch(requisicao, {
        redirect: "manual"
      });

      const headers = new Headers(resposta.headers);
      headers.set("Cache-Control", "no-store");

      return new Response(resposta.body, {
        status: resposta.status,
        statusText: resposta.statusText,
        headers
      });
    }

    return env.ASSETS.fetch(request);
  }
};
