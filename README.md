# lad-assets

Catálogo público de backgrounds (imagens e vídeos em loop) para o terminal do LAD / live-code-ui.

Consumido pela feature SPEC-141 (Selectable Terminal Backgrounds): o app lê `manifest.json`, exibe os previews num picker em grid e baixa o `full` sob demanda, cacheando localmente.

## Estrutura

```
lad-assets/
  manifest.json          # fonte da lista (gerado pelo script, não editar à mão)
  labels.json            # nomes exibíveis opcionais (id -> "Nome pt-BR")
  source/<nome>.<ext>    # ENTRADA: arquivos crus curados (imagem ou vídeo)
  full/<nome>.<ext>      # SAÍDA gerada: asset servido (vídeo com loop seamless)
  preview/<nome>.<ext>   # SAÍDA gerada: miniatura/loop menor + poster
  scripts/generate-previews.sh
```

- `source/` — você coloca os arquivos crus aqui. É a única pasta de entrada.
- `full/` — gerado pelo script. Para vídeo, o loop é fechado por crossfade quando a costura é visível (SSIM primeiro↔último frame < 0.7); clipes já bem fechados são só remuxados. É este arquivo que o app baixa e aplica como background.
- `preview/` — gerado pelo script: para vídeo, um loop menor `.mp4` (herda o loop seamless do full) + um poster `.jpg`; para imagem, uma versão menor `.jpg`.
- O nome do arquivo vira o `id` do asset. O rótulo exibido é derivado do nome (`ondas-do-mar.mp4` → "Ondas Do Mar"); para controlar o texto em pt-BR, mapeie em `labels.json` (ex.: `{ "ondas-do-mar": "Ondas do mar" }`).

## Servindo

- Manifesto (buscado sempre fresco): `https://raw.githubusercontent.com/live-lad/lad-assets/main/manifest.json`
- Bytes pesados (CDN): `https://cdn.jsdelivr.net/gh/live-lad/lad-assets@main/full/<arquivo>` e `.../preview/<arquivo>`

## Limites de tamanho (IMPORTANTE)

Existem dois tetos diferentes, e o que realmente importa é o do CDN:

- **jsDelivr rejeita arquivos > 20 MB** com `403 File size exceeded the configured limit of 20 MB`. Como o app baixa o `full` via jsDelivr, **todo arquivo em `full/` DEVE ter ≤ 20 MB** — senão o endpoint `/api/backgrounds/<id>/ensure` do app responde `502 Bad Gateway` e o background não carrega. Mire ~18 MB para ter folga.
- **GitHub bloqueia push de arquivos > 100 MB** (e avisa a partir de 50 MB). Vale para qualquer blob no histórico enviado.
- `source/` **não é servido** (não aparece no `manifest.json`); o app nunca baixa o cru. Ele só ocupa espaço no repo, então precisa respeitar apenas o limite de 100 MB do GitHub.

⚠️ **O `generate-previews.sh` NÃO aplica esses limites nem faz downscale** — ele mantém a resolução original do `source` (um vídeo 4K vira um `full` 4K de dezenas de MB, que o jsDelivr recusa). Ao curar vídeos pesados/4K, normalize para **1080p** e comprima o `full` para ≤ 20 MB antes de publicar. Receita usada (two-pass, mantém o loop seamless):

```
# alvo ~18 MB: bitrate_kbps = 18 * 8192 / duracao_em_segundos
ffmpeg -y -i full/<id>.mp4 -an -c:v libx264 -preset slow -b:v <kbps>k -pass 1 \
  -vf "scale='min(iw,trunc(iw*1080/ih/2)*2)':'min(ih,1080)':flags=lanczos,format=yuv420p" -f mp4 /dev/null
ffmpeg -y -i full/<id>.mp4 -an -c:v libx264 -preset slow -b:v <kbps>k -pass 2 \
  -vf "scale='min(iw,trunc(iw*1080/ih/2)*2)':'min(ih,1080)':flags=lanczos,format=yuv420p" \
  -pix_fmt yuv420p -movflags +faststart full/<id>.mp4
```

Depois regere `preview/` + poster a partir do novo `full` e atualize a `version` (hash) no `manifest.json`.

### Cache do jsDelivr

As URLs usam `@main`, que o jsDelivr cacheia por até ~12 h. Depois de publicar uma versão nova de um arquivo já existente, purgue o cache para o app não continuar recebendo o arquivo antigo:

```
curl -s https://purge.jsdelivr.net/gh/live-lad/lad-assets@main/full/<id>.mp4
```

(o purge é assíncrono — pode levar alguns minutos para propagar em todos os edges).

## Gerar previews e manifesto

Depois de colocar os arquivos em `source/`:

```
bash scripts/generate-previews.sh
```

O script recria `full/`, `preview/` e `manifest.json` a partir do conteúdo de `source/` (idempotente). A `version` de cada asset é o hash do arquivo full gerado — trocar o source invalida o cache no app automaticamente.

## Licença dos assets

Use apenas mídia de licença permissiva / CC0 liberada para uso comercial sem atribuição (Pixabay, Pexels, Coverr, Unsplash). Não adicione material copyleft (GPL) ou de proveniência incerta.
