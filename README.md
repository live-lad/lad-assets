# lad-assets

Catálogo público de backgrounds (imagens e vídeos em loop) para o terminal do LAD / live-code-ui.

Consumido pela feature SPEC-141 (Selectable Terminal Backgrounds): o app lê `manifest.json`, exibe os previews num picker em grid e baixa o `full` sob demanda, cacheando localmente.

## Estrutura

```
lad-assets/
  manifest.json          # fonte da lista (gerado pelo script, não editar à mão)
  labels.json            # nomes exibíveis opcionais (id -> "Nome pt-BR")
  full/<nome>.<ext>      # asset em resolução cheia (imagem ou vídeo)
  preview/<nome>.<ext>   # miniatura/loop menor gerado (mesmo <nome> do full)
  scripts/generate-previews.sh
```

- `full/` — você coloca os arquivos aqui (5 vídeos + 5 imagens no v1).
- `preview/` — gerado pelo script: para vídeo, um loop menor `.mp4` + um poster `.jpg`; para imagem, uma versão menor `.jpg`.
- O nome do arquivo vira o `id` do asset. O rótulo exibido é derivado do nome (`ondas-do-mar.mp4` → "Ondas Do Mar"); para controlar o texto em pt-BR, mapeie em `labels.json` (ex.: `{ "ondas-do-mar": "Ondas do mar" }`).

## Servindo

- Manifesto (buscado sempre fresco): `https://raw.githubusercontent.com/live-lad/lad-assets/main/manifest.json`
- Bytes pesados (CDN): `https://cdn.jsdelivr.net/gh/live-lad/lad-assets@main/full/<arquivo>` e `.../preview/<arquivo>`

## Gerar previews e manifesto

Depois de colocar os arquivos em `full/`:

```
bash scripts/generate-previews.sh
```

O script recria `preview/` e `manifest.json` a partir do conteúdo de `full/`. A `version` de cada asset é o hash do arquivo full — trocar o arquivo invalida o cache no app automaticamente.

## Licença dos assets

Use apenas mídia de licença permissiva / CC0 liberada para uso comercial sem atribuição (Pixabay, Pexels, Coverr, Unsplash). Não adicione material copyleft (GPL) ou de proveniência incerta.
