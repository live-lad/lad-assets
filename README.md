# lad-assets

Catálogo público de assets para o terminal do LAD / live-code-ui: **backgrounds** (imagens e vídeos em loop) e **sons ambientes** (áudio em loop, feature Ambience).

Consumido pelo app: ele lê `manifest.json`, exibe os assets num picker (grid de backgrounds + mixer de sons) e baixa o `full` sob demanda, cacheando localmente. Backgrounds vêm da SPEC-141; os sons `type: "sound"` da SPEC-149 (Ambience).

## Estrutura

```
lad-assets/
  manifest.json          # fonte da lista (gerado pelo script, não editar à mão)
  labels.json            # nomes exibíveis opcionais (id -> "Nome pt-BR")
  licenses.json          # licença por som (id -> "CC BY" | "CC0" | ...); usado só p/ áudio
  source/<nome>.<ext>    # ENTRADA: arquivos crus curados (imagem, vídeo ou áudio)
  full/<nome>.<ext>      # SAÍDA gerada: asset servido (vídeo loop seamless / imagem / áudio mp3)
  preview/<nome>.<ext>   # SAÍDA gerada: miniatura/loop menor + poster (só vídeo/imagem)
  scripts/generate-previews.sh
  SOUNDS_LICENSING.md    # créditos e licenças dos sons
```

- `source/` — você coloca os arquivos crus aqui. É a única pasta de entrada. Aceita vídeo (`.mp4/.webm/.mov/.mkv`), imagem (`.jpg/.png/.webp`) e áudio (`.mp3/.ogg/.wav/.m4a/.flac/.opus`).
- `full/` — gerado pelo script. Para vídeo, o loop é fechado por crossfade quando a costura é visível; clipes já bem fechados são só remuxados. Para áudio, o source é transcodificado para `.mp3` (`libmp3lame -q:a 4`). É este arquivo que o app baixa.
- `preview/` — gerado pelo script apenas para vídeo/imagem (miniatura + poster). **Áudio não tem preview** — o app usa um ícone (campo `icon`, igual ao `id`) e o nome.
- O nome do arquivo vira o `id` do asset. O rótulo exibido é derivado do nome (`ondas-do-mar.mp4` → "Ondas Do Mar"); para controlar o texto em pt-BR, mapeie em `labels.json` (ex.: `{ "ondas-do-mar": "Ondas do mar" }`).
- **Sons:** além do `labels.json`, mapeie a licença em `licenses.json` (ex.: `{ "rain": "CC BY" }`) — o script grava o campo `license` no manifest. Documente autor/fonte em `SOUNDS_LICENSING.md`.

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

**Backgrounds:** use apenas mídia de licença permissiva / CC0 liberada para uso comercial sem atribuição (Pixabay, Pexels, Coverr, Unsplash). Não adicione material copyleft (GPL) ou de proveniência incerta.

**Sons:** cada som carrega a licença original do autor (`licenses.json` + `SOUNDS_LICENSING.md`). Sons `CC BY` e `CC BY-SA` são permitidos, mas exigem atribuição — mantenha autor e fonte em `SOUNDS_LICENSING.md`. A cláusula share-alike dos `CC BY-SA` recai sobre o arquivo de áudio, não sobre o app.
