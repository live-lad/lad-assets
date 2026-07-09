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

## Gerar previews e manifesto

Depois de colocar os arquivos em `source/`:

```
bash scripts/generate-previews.sh
```

O script recria `full/`, `preview/` e `manifest.json` a partir do conteúdo de `source/` (idempotente). A `version` de cada asset é o hash do arquivo full gerado — trocar o source invalida o cache no app automaticamente.

## Licença dos assets

Use apenas mídia de licença permissiva / CC0 liberada para uso comercial sem atribuição (Pixabay, Pexels, Coverr, Unsplash). Não adicione material copyleft (GPL) ou de proveniência incerta.
