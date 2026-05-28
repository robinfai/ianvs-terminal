# Ianvs Terminal product site

这是 `ianvs` 第一版静态产品官网。它没有构建步骤，也不依赖 npm。

## 本地预览

```bash
python3 -m http.server 8080 --directory site
```

然后打开：

```text
http://localhost:8080/
```

## 验证

```bash
python3 site/tools/validate_site.py
```

验证脚本会检查：

- 五个页面是否存在。
- 页面是否引用公共 CSS 和 JS。
- 内部链接是否有效。
- 是否保留主题切换控件。
- 是否出现第一版禁止使用的过度承诺文案。

## 页面

- `index.html`
- `features/index.html`
- `technology/index.html`
- `roadmap/index.html`
- `open-source/index.html`
