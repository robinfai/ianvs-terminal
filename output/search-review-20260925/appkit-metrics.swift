import AppKit
let fonts: [(String, NSFont)] = [
  ("system", NSFont.systemFont(ofSize: 0)),
  ("control", NSFont.controlContentFont(ofSize: 0)),
  ("menu", NSFont.menuFont(ofSize: 0)),
  ("label", NSFont.labelFont(ofSize: 0)),
  ("small", NSFont.systemFont(ofSize: NSFont.smallSystemFontSize))
]
for (name, font) in fonts {
  print("\(name): family=\(font.familyName ?? "unknown"), size=\(font.pointSize), ascender=\(font.ascender), descender=\(font.descender), leading=\(font.leading)")
}
for size in [NSControl.ControlSize.regular, .small, .mini] {
  let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 260, height: 40))
  field.controlSize = size
  field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: size))
  print("search controlSize=\(size.rawValue): font=\(field.font!.pointSize), intrinsic=\(field.intrinsicContentSize), fitting=\(field.fittingSize)")
}
