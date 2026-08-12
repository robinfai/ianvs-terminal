use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use syn::parse::Parser;
use syn::punctuated::Punctuated;
use syn::visit::{self, Visit};
use syn::{
    Attribute, Expr, File, Item, ItemMod, Macro, Meta, Path as SynPath, Token, Type, UseTree,
};

const SESSION_SOURCE: &str = include_str!("../src/session.rs");

// These adversarial sources are real Rust modules, not merely parser input.
// Keeping them in the integration-test crate proves the escape examples stay
// semantically compilable as the AST gate evolves.
#[allow(dead_code)]
#[path = "fixtures/session_architecture/block_local_import_escape.rs"]
mod block_local_import_escape_fixture;
#[allow(dead_code)]
#[path = "fixtures/session_architecture/protocol_host_parent_escape.rs"]
mod protocol_host_parent_escape_fixture;
#[allow(dead_code)]
#[path = "fixtures/session_architecture/raw_parser_drain_escape.rs"]
mod raw_parser_drain_escape_fixture;
#[allow(dead_code)]
#[path = "fixtures/session_architecture/raw_try_drain_escape.rs"]
mod raw_try_drain_escape_fixture;
#[allow(dead_code)]
#[path = "fixtures/session_architecture/raw_try_helper_drain_escape.rs"]
mod raw_try_helper_drain_escape_fixture;
#[allow(dead_code)]
#[path = "fixtures/session_architecture/recursive_associated_type_escape.rs"]
mod recursive_associated_type_escape_fixture;
#[allow(dead_code)]
#[path = "fixtures/session_architecture/recursive_supertrait_escape.rs"]
mod recursive_supertrait_escape_fixture;
#[allow(dead_code)]
#[path = "fixtures/session_architecture/recursive_type_alias_escape.rs"]
mod recursive_type_alias_escape_fixture;

fn source_path(relative: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join(relative)
}

fn parse_rust(path: &Path) -> File {
    let source = fs::read_to_string(path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()));
    syn::parse_file(&source)
        .unwrap_or_else(|error| panic!("failed to parse {}: {error}", path.display()))
}

fn has_cfg_test(attributes: &[Attribute]) -> bool {
    attributes.iter().any(|attribute| {
        attribute.path().is_ident("cfg")
            && attribute
                .meta
                .require_list()
                .is_ok_and(|list| list.tokens.to_string().replace(' ', "") == "test")
    })
}

fn external_module_path(owner: &Path, module: &ItemMod) -> Option<PathBuf> {
    if module.content.is_some() {
        return None;
    }
    let parent = owner.parent().expect("Rust source has a parent directory");
    let owner_stem = owner.file_stem()?.to_str()?;
    let module_name = module.ident.to_string();
    let base = if matches!(owner_stem, "lib" | "main" | "mod") {
        parent.to_path_buf()
    } else {
        parent.join(owner_stem)
    };
    let flat = base.join(format!("{module_name}.rs"));
    if flat.is_file() {
        Some(flat)
    } else {
        let nested = base.join(module_name).join("mod.rs");
        nested.is_file().then_some(nested)
    }
}

fn module_graph(root: &Path) -> BTreeMap<PathBuf, BTreeSet<PathBuf>> {
    fn visit_file(
        path: PathBuf,
        graph: &mut BTreeMap<PathBuf, BTreeSet<PathBuf>>,
        visited: &mut BTreeSet<PathBuf>,
    ) {
        if !visited.insert(path.clone()) {
            return;
        }
        let syntax = parse_rust(&path);
        let source_indirections = source_indirection_violations(&syntax);
        assert!(
            source_indirections.is_empty(),
            "{} uses forbidden source indirection: {source_indirections:?}",
            path.display()
        );
        let mut children = BTreeSet::new();
        for item in &syntax.items {
            let Item::Mod(module) = item else { continue };
            if has_cfg_test(&module.attrs) {
                continue;
            }
            if let Some(child) = external_module_path(&path, module) {
                children.insert(child);
            }
        }
        graph.insert(path, children.clone());
        for child in children {
            visit_file(child, graph, visited);
        }
    }

    let mut graph = BTreeMap::new();
    visit_file(root.to_path_buf(), &mut graph, &mut BTreeSet::new());
    graph
}

fn production_definition_names(file: &File) -> BTreeSet<String> {
    let mut definitions = BTreeSet::new();
    for item in &file.items {
        match item {
            Item::Fn(function) if !has_cfg_test(&function.attrs) => {
                definitions.insert(function.sig.ident.to_string());
            }
            Item::Impl(implementation) if !has_cfg_test(&implementation.attrs) => {
                for implementation_item in &implementation.items {
                    if let syn::ImplItem::Fn(function) = implementation_item {
                        definitions.insert(function.sig.ident.to_string());
                    }
                }
            }
            Item::Struct(item) => {
                definitions.insert(item.ident.to_string());
            }
            Item::Enum(item) => {
                definitions.insert(item.ident.to_string());
            }
            Item::Trait(item) => {
                definitions.insert(item.ident.to_string());
            }
            _ => {}
        }
    }
    definitions
}

fn imported_leaf_names(tree: &UseTree, names: &mut BTreeSet<String>) {
    match tree {
        UseTree::Path(path) => imported_leaf_names(&path.tree, names),
        UseTree::Name(name) => {
            names.insert(name.ident.to_string());
        }
        UseTree::Rename(rename) => {
            names.insert(rename.rename.to_string());
        }
        UseTree::Group(group) => {
            for item in &group.items {
                imported_leaf_names(item, names);
            }
        }
        UseTree::Glob(_) => {}
    }
}

fn imported_paths(tree: &UseTree, prefix: &mut Vec<String>, paths: &mut BTreeSet<String>) {
    match tree {
        UseTree::Path(path) => {
            prefix.push(path.ident.to_string());
            imported_paths(&path.tree, prefix, paths);
            prefix.pop();
        }
        UseTree::Name(name) => {
            prefix.push(name.ident.to_string());
            paths.insert(prefix.join("::"));
            prefix.pop();
        }
        UseTree::Rename(rename) => {
            prefix.push(rename.ident.to_string());
            paths.insert(prefix.join("::"));
            prefix.pop();
        }
        UseTree::Glob(_) => {
            prefix.push("*".to_string());
            paths.insert(prefix.join("::"));
            prefix.pop();
        }
        UseTree::Group(group) => {
            for item in &group.items {
                imported_paths(item, prefix, paths);
            }
        }
    }
}

#[derive(Default)]
struct ProductionImportCollector {
    paths: BTreeSet<String>,
}

impl<'ast> Visit<'ast> for ProductionImportCollector {
    fn visit_item_fn(&mut self, function: &'ast syn::ItemFn) {
        if !has_cfg_test(&function.attrs) {
            visit::visit_item_fn(self, function);
        }
    }

    fn visit_item_impl(&mut self, implementation: &'ast syn::ItemImpl) {
        if !has_cfg_test(&implementation.attrs) {
            visit::visit_item_impl(self, implementation);
        }
    }

    fn visit_item_mod(&mut self, module: &'ast ItemMod) {
        if !has_cfg_test(&module.attrs) {
            visit::visit_item_mod(self, module);
        }
    }

    fn visit_item_use(&mut self, import: &'ast syn::ItemUse) {
        if !has_cfg_test(&import.attrs) {
            imported_paths(&import.tree, &mut Vec::new(), &mut self.paths);
        }
    }
}

fn production_import_paths(file: &File) -> BTreeSet<String> {
    let mut collector = ProductionImportCollector::default();
    collector.visit_file(file);
    collector.paths
}

struct DependencyPathCollector {
    local_roots: BTreeSet<String>,
    dependency_roots: BTreeSet<String>,
}

#[derive(Default)]
struct ProductionPathCollector {
    paths: BTreeSet<String>,
}

impl<'ast> Visit<'ast> for ProductionPathCollector {
    fn visit_item_fn(&mut self, function: &'ast syn::ItemFn) {
        if !has_cfg_test(&function.attrs) {
            visit::visit_item_fn(self, function);
        }
    }

    fn visit_item_mod(&mut self, module: &'ast ItemMod) {
        if !has_cfg_test(&module.attrs) {
            visit::visit_item_mod(self, module);
        }
    }

    fn visit_path(&mut self, path: &'ast SynPath) {
        self.paths.insert(
            path.segments
                .iter()
                .map(|segment| segment.ident.to_string())
                .collect::<Vec<_>>()
                .join("::"),
        );
        visit::visit_path(self, path);
    }
}

fn production_paths(file: &File) -> BTreeSet<String> {
    let mut collector = ProductionPathCollector::default();
    collector.visit_file(file);
    collector.paths
}

#[derive(Default)]
struct SourceIndirectionCollector {
    violations: Vec<String>,
}

fn meta_contains_path_override(meta: &Meta) -> bool {
    match meta {
        Meta::Path(path) => path.is_ident("path"),
        Meta::NameValue(value) => value.path.is_ident("path"),
        Meta::List(list) if list.path.is_ident("cfg_attr") => {
            let Ok(arguments) =
                Punctuated::<Meta, Token![,]>::parse_terminated.parse2(list.tokens.clone())
            else {
                return true;
            };
            arguments.iter().skip(1).any(meta_contains_path_override)
        }
        Meta::List(_) => false,
    }
}

fn attribute_contains_path_override(attribute: &Attribute) -> bool {
    attribute.path().is_ident("path") || meta_contains_path_override(&attribute.meta)
}

impl<'ast> Visit<'ast> for SourceIndirectionCollector {
    fn visit_item_fn(&mut self, function: &'ast syn::ItemFn) {
        if !has_cfg_test(&function.attrs) {
            visit::visit_item_fn(self, function);
        }
    }

    fn visit_item_mod(&mut self, module: &'ast ItemMod) {
        if has_cfg_test(&module.attrs) {
            return;
        }
        if module.attrs.iter().any(attribute_contains_path_override) {
            self.violations
                .push(format!("#[path] module {}", module.ident));
        }
        visit::visit_item_mod(self, module);
    }

    fn visit_macro(&mut self, invocation: &'ast Macro) {
        if invocation
            .path
            .segments
            .last()
            .is_some_and(|segment| segment.ident == "include")
        {
            self.violations.push("include! macro".to_string());
        }
        visit::visit_macro(self, invocation);
    }
}

fn source_indirection_violations(file: &File) -> Vec<String> {
    let mut collector = SourceIndirectionCollector::default();
    collector.visit_file(file);
    collector.violations
}

fn expression_reaches_terminal_field(expression: &Expr) -> bool {
    match expression {
        Expr::Field(field) => {
            matches!(&field.member, syn::Member::Named(name) if name == "terminal")
                || expression_reaches_terminal_field(&field.base)
        }
        Expr::Group(group) => expression_reaches_terminal_field(&group.expr),
        Expr::Paren(paren) => expression_reaches_terminal_field(&paren.expr),
        Expr::Reference(reference) => expression_reaches_terminal_field(&reference.expr),
        Expr::Try(try_expression) => expression_reaches_terminal_field(&try_expression.expr),
        Expr::Call(call) => {
            expression_reaches_terminal_field(&call.func)
                || call.args.iter().any(expression_reaches_terminal_field)
        }
        Expr::Path(path) => path.path.is_ident("terminal"),
        _ => false,
    }
}

#[derive(Default)]
struct RawParserDrainCollector {
    drains: Vec<String>,
    current_function: Option<String>,
    function_depth: usize,
    module_depth: usize,
}

fn is_product_event_store_poll(receiver: &Expr) -> bool {
    let Expr::Try(try_expression) = receiver else {
        return false;
    };
    let Expr::MethodCall(get_call) = &*try_expression.expr else {
        return false;
    };
    get_call.method == "get"
        && matches!(&*get_call.receiver, Expr::Path(path) if path.path.is_ident("STORE"))
        && get_call.args.len() == 1
        && matches!(get_call.args.first(), Some(Expr::Path(path)) if path.path.is_ident("session_id"))
}

impl<'ast> Visit<'ast> for RawParserDrainCollector {
    fn visit_item_fn(&mut self, function: &'ast syn::ItemFn) {
        if has_cfg_test(&function.attrs) {
            return;
        }
        let previous = self
            .current_function
            .replace(function.sig.ident.to_string());
        self.function_depth += 1;
        visit::visit_item_fn(self, function);
        self.function_depth -= 1;
        self.current_function = previous;
    }

    fn visit_impl_item_fn(&mut self, function: &'ast syn::ImplItemFn) {
        if has_cfg_test(&function.attrs) {
            return;
        }
        let previous = self
            .current_function
            .replace(function.sig.ident.to_string());
        self.function_depth += 1;
        visit::visit_impl_item_fn(self, function);
        self.function_depth -= 1;
        self.current_function = previous;
    }

    fn visit_item_mod(&mut self, module: &'ast ItemMod) {
        if has_cfg_test(&module.attrs) {
            return;
        }
        self.module_depth += 1;
        visit::visit_item_mod(self, module);
        self.module_depth -= 1;
    }

    fn visit_expr_method_call(&mut self, call: &'ast syn::ExprMethodCall) {
        if call.method == "poll_events" {
            let is_exact_product_event_endpoint = self.module_depth == 0
                && self.function_depth == 1
                && self.current_function.as_deref() == Some("take_events")
                && is_product_event_store_poll(&call.receiver);
            if is_exact_product_event_endpoint {
                // This is the one public product-event drain in session.rs;
                // every other production poll_events call fails closed.
            } else if expression_reaches_terminal_field(&call.receiver) {
                self.drains.push("terminal.poll_events()".to_string());
            } else {
                let function = self.current_function.as_deref().unwrap_or("<unknown>");
                self.drains.push(format!("poll_events() in {function}"));
            }
        }
        visit::visit_expr_method_call(self, call);
    }

    fn visit_expr_call(&mut self, call: &'ast syn::ExprCall) {
        let is_poll_events = matches!(&*call.func, Expr::Path(path)
            if path.path.segments.last().is_some_and(|segment| segment.ident == "poll_events"));
        if is_poll_events {
            let function = self.current_function.as_deref().unwrap_or("<unknown>");
            self.drains
                .push(format!("associated poll_events() in {function}"));
        }
        visit::visit_expr_call(self, call);
    }
}

fn raw_parser_drain_violations(file: &File) -> Vec<String> {
    let mut collector = RawParserDrainCollector::default();
    collector.visit_file(file);
    let paths = production_paths(file);
    collector.drains.extend(
        paths
            .into_iter()
            .filter(|path| {
                path.ends_with("Terminal::poll_events")
                    || path.ends_with("ParserTerminalEvent::poll_events")
            })
            .map(|path| format!("raw parser drain path {path}")),
    );
    collector.drains
}

fn definition_paths(file: &File) -> BTreeMap<String, BTreeSet<String>> {
    let mut definitions = BTreeMap::new();
    for item in &file.items {
        let definition = match item {
            Item::Enum(item) => Some((item.ident.to_string(), item.attrs.as_slice())),
            Item::Struct(item) => Some((item.ident.to_string(), item.attrs.as_slice())),
            Item::Trait(item) => Some((item.ident.to_string(), item.attrs.as_slice())),
            Item::Type(item) => Some((item.ident.to_string(), item.attrs.as_slice())),
            Item::Union(item) => Some((item.ident.to_string(), item.attrs.as_slice())),
            _ => None,
        };
        let Some((name, attributes)) = definition else {
            continue;
        };
        if has_cfg_test(attributes) {
            continue;
        }
        let mut collector = ProductionPathCollector::default();
        match item {
            Item::Enum(item) => collector.visit_item_enum(item),
            Item::Struct(item) => collector.visit_item_struct(item),
            Item::Trait(item) => collector.visit_item_trait(item),
            Item::Type(item) => collector.visit_item_type(item),
            Item::Union(item) => collector.visit_item_union(item),
            _ => unreachable!(),
        }
        definitions.insert(name, collector.paths);
    }
    definitions
}

fn recursive_type_paths(file: &File, root: &str) -> BTreeSet<String> {
    let definitions = definition_paths(file);
    let mut pending = vec![root.to_string()];
    let mut visited = BTreeSet::new();
    let mut paths = BTreeSet::new();
    while let Some(name) = pending.pop() {
        if !visited.insert(name.clone()) {
            continue;
        }
        let Some(definition_paths) = definitions.get(&name) else {
            continue;
        };
        for path in definition_paths {
            paths.insert(path.clone());
            if let Some(local_name) = path.split("::").last()
                && definitions.contains_key(local_name)
            {
                pending.push(local_name.to_string());
            }
        }
    }
    paths
}

fn forbidden_parent_paths(paths: &BTreeSet<String>) -> Vec<String> {
    paths
        .iter()
        .filter(|path| {
            path.starts_with("crate::")
                && path.split("::").any(|segment| {
                    matches!(
                        segment,
                        "Terminal"
                            | "TerminalState"
                            | "retained_row_for_abs_row"
                            | "selection_text_for_terminal"
                    )
                })
        })
        .cloned()
        .collect()
}

fn simple_type_name(ty: &Type) -> Option<String> {
    let Type::Path(path) = ty else { return None };
    path.path
        .segments
        .last()
        .map(|segment| segment.ident.to_string())
}

fn implementation_pairs(file: &File) -> BTreeSet<String> {
    file.items
        .iter()
        .filter_map(|item| {
            let Item::Impl(item) = item else { return None };
            let (_, trait_path, _) = item.trait_.as_ref()?;
            let trait_name = trait_path.segments.last()?.ident.to_string();
            let target = simple_type_name(&item.self_ty)?;
            Some(format!("{trait_name} for {target}"))
        })
        .collect()
}

fn protocol_host_responsibility_violations(file: &File) -> Vec<String> {
    let mut violations = source_indirection_violations(file);
    let allowed_imports = [
        "crate::model::TerminalSelectionRequest",
        "par_term_emu_core_rust::terminal::Terminal",
        "par_term_emu_core_rust::terminal::TerminalEvent",
        "super::TerminalState",
        "super::protocol_callbacks::ProtocolCallbackBatch",
        "super::protocol_callbacks::ProtocolCallbackPolicy",
        "super::protocol_callbacks::ProtocolCompletedTransfer",
        "super::protocol_callbacks::ProtocolEventControl",
        "super::protocol_callbacks::ProtocolHostContext",
        "super::protocol_callbacks::ProtocolTransferControl",
        "super::protocol_callbacks::callback_events_from_parser_events",
        "super::retained_row_for_abs_row",
        "super::selection_text_for_terminal",
    ]
    .into_iter()
    .map(str::to_string)
    .collect::<BTreeSet<_>>();
    let imports = production_import_paths(file);
    for import in imports.difference(&allowed_imports) {
        violations.push(format!("unexpected protocol_host import {import}"));
    }
    for import in allowed_imports.difference(&imports) {
        violations.push(format!("missing protocol_host import {import}"));
    }

    let allowed_definitions = [
        "cancel_protocol_upload",
        "drain_protocol_callback_batch",
        "poll_protocol_events",
        "resolve_annotation_selection",
        "resolve_report_variable",
        "retain_protocol_download",
        "take_completed_protocol_transfer",
    ]
    .into_iter()
    .map(str::to_string)
    .collect::<BTreeSet<_>>();
    let definitions = production_definition_names(file);
    for definition in definitions.difference(&allowed_definitions) {
        violations.push(format!("unexpected protocol_host definition {definition}"));
    }
    for definition in allowed_definitions.difference(&definitions) {
        violations.push(format!("missing protocol_host definition {definition}"));
    }

    let expected_impls = [
        "ProtocolEventControl for Terminal",
        "ProtocolHostContext for TerminalState",
        "ProtocolTransferControl for Terminal",
        "ProtocolTransferControl for TerminalState",
    ]
    .into_iter()
    .map(str::to_string)
    .collect::<BTreeSet<_>>();
    let impls = implementation_pairs(file);
    for implementation in impls.symmetric_difference(&expected_impls) {
        violations.push(format!(
            "unexpected/missing protocol_host impl {implementation}"
        ));
    }

    let host_paths = production_paths(file);
    let qualified_dependency_allowlist = [
        "crate::model::TerminalSelectionRequest",
        "par_term_emu_core_rust::terminal::Terminal",
        "par_term_emu_core_rust::terminal::TerminalEvent",
        "super::TerminalState",
        "super::protocol_callbacks",
        "super::protocol_callbacks::ProtocolCallbackBatch",
        "super::protocol_callbacks::ProtocolCallbackPolicy",
        "super::protocol_callbacks::ProtocolCompletedTransfer",
        "super::protocol_callbacks::ProtocolEventControl",
        "super::protocol_callbacks::ProtocolHostContext",
        "super::protocol_callbacks::ProtocolTransferControl",
        "super::protocol_callbacks::callback_events_from_parser_events",
        "super::retained_row_for_abs_row",
        "super::selection_text_for_terminal",
    ]
    .into_iter()
    .collect::<BTreeSet<_>>();
    for path in &host_paths {
        let is_qualified_dependency = path.contains("::")
            && matches!(
                path.split("::").next(),
                Some("crate" | "par_term_emu_core_rust" | "super")
            );
        if is_qualified_dependency && !qualified_dependency_allowlist.contains(path.as_str()) {
            violations.push(format!(
                "unexpected qualified protocol_host dependency {path}"
            ));
        }
    }

    let variant_paths = host_paths
        .into_iter()
        .filter(|path| path.starts_with("ParserTerminalEvent::"))
        .collect::<Vec<_>>();
    for path in variant_paths {
        violations.push(format!("protocol_host maps parser variant {path}"));
    }
    violations
}

fn parse_fixture(name: &str) -> File {
    parse_rust(&source_path(&format!(
        "tests/fixtures/session_architecture/{name}.rs"
    )))
}

impl<'ast> Visit<'ast> for DependencyPathCollector {
    fn visit_item_fn(&mut self, function: &'ast syn::ItemFn) {
        if !has_cfg_test(&function.attrs) {
            visit::visit_item_fn(self, function);
        }
    }

    fn visit_item_mod(&mut self, module: &'ast ItemMod) {
        if !has_cfg_test(&module.attrs) {
            visit::visit_item_mod(self, module);
        }
    }

    fn visit_path(&mut self, path: &'ast SynPath) {
        if path.segments.len() > 1 {
            let root = path.segments[0].ident.to_string();
            if !self.local_roots.contains(&root) {
                self.dependency_roots.insert(root);
            }
        }
        visit::visit_path(self, path);
    }
}

fn dependency_roots(file: &File) -> BTreeSet<String> {
    let mut local_roots = production_definition_names(file);
    for item in &file.items {
        if let Item::Use(import) = item {
            imported_leaf_names(&import.tree, &mut local_roots);
        }
    }
    local_roots.extend(
        [
            "Box", "Option", "Result", "Self", "String", "Vec", "char", "str",
        ]
        .into_iter()
        .map(str::to_string),
    );
    let mut collector = DependencyPathCollector {
        local_roots,
        dependency_roots: BTreeSet::new(),
    };
    collector.visit_file(file);
    collector.dependency_roots.extend(
        production_import_paths(file)
            .into_iter()
            .filter_map(|path| path.split("::").next().map(str::to_string)),
    );
    collector.dependency_roots
}

#[test]
fn session_orchestrator_stays_within_its_post_extraction_line_budget() {
    const SESSION_LINE_BUDGET: usize = 13_500;
    let line_count = SESSION_SOURCE.lines().count();

    assert!(
        line_count <= SESSION_LINE_BUDGET,
        "session.rs has {line_count} lines, above its {SESSION_LINE_BUDGET}-line budget; \
         move another cohesive responsibility behind a session submodule"
    );
}

#[test]
fn protocol_callback_module_is_an_external_child_of_session() {
    let session = source_path("src/session.rs");
    let callbacks = source_path("src/session/protocol_callbacks.rs");
    let host = source_path("src/session/protocol_host.rs");
    let graph = module_graph(&session);
    let session_children = graph
        .get(&session)
        .expect("session.rs must be present in its module graph");

    assert!(
        session_children.contains(&callbacks),
        "session module graph must retain protocol_callbacks as an external child"
    );
    assert!(
        session_children.contains(&host),
        "session module graph must retain protocol_host as an explicit external adapter"
    );
}

#[test]
fn parser_and_escape_sequence_handlers_stay_out_of_session_orchestration() {
    let session = parse_rust(&source_path("src/session.rs"));
    let callbacks = parse_rust(&source_path("src/session/protocol_callbacks.rs"));
    let session_definitions = production_definition_names(&session);
    let callback_definitions = production_definition_names(&callbacks);

    let leaked_handlers = session_definitions
        .iter()
        .filter(|name| {
            ["consume_", "handle_", "parse_"]
                .iter()
                .any(|prefix| name.starts_with(prefix))
                && ["osc", "dcs", "csi"]
                    .iter()
                    .any(|protocol| name.contains(protocol))
                || name.contains("callback_event_from_parser")
        })
        .collect::<Vec<_>>();
    assert!(
        leaked_handlers.is_empty(),
        "parser/OSC/DCS/CSI handlers leaked into session.rs: {leaked_handlers:?}"
    );
    for forbidden in ["CallbackObserver", "HostProtocolState", "Osc5522WriteState"] {
        assert!(
            !session_definitions.contains(forbidden),
            "protocol parser state leaked into session.rs: {forbidden}"
        );
    }

    let session_imports = production_import_paths(&session);
    let session_paths = production_paths(&session);
    assert!(
        session_imports
            .iter()
            .all(|path| path != "par_term_emu_core_rust::terminal::TerminalEvent"),
        "session.rs production code must not import the generated parser event type: {session_imports:?}"
    );
    let raw_parser_paths = session_paths
        .iter()
        .filter(|path| {
            path.split("::")
                .any(|segment| segment == "ParserTerminalEvent")
                || path.starts_with("par_term_emu_core_rust::terminal::TerminalEvent")
        })
        .collect::<Vec<_>>();
    assert!(
        raw_parser_paths.is_empty(),
        "session.rs production AST handles raw parser events directly: {raw_parser_paths:?}"
    );
    let raw_parser_drains = raw_parser_drain_violations(&session);
    assert!(
        raw_parser_drains.is_empty(),
        "session.rs production code drains terminal parser events directly: {raw_parser_drains:?}"
    );
    assert!(
        session_imports.contains("protocol_host::drain_protocol_callback_batch"),
        "session.rs must consume parser callbacks through protocol_host's batch facade"
    );
    assert!(
        !session_imports.contains("protocol_callbacks::callback_events_from_parser_events"),
        "session.rs production code must not import the raw parser-event mapper"
    );

    for expected in [
        "HostProtocolState",
        "consume_osc",
        "consume_dcs",
        "consume_csi",
        "handle_osc5522",
        "callback_events_from_parser_events",
        "parse_osc5522_metadata",
    ] {
        assert!(
            callback_definitions.contains(expected),
            "protocol callback module lost expected AST definition: {expected}"
        );
    }
}

#[test]
fn protocol_callbacks_depend_only_on_narrow_allowed_modules() {
    let callbacks = parse_rust(&source_path("src/session/protocol_callbacks.rs"));
    let source_indirections = source_indirection_violations(&callbacks);
    assert!(
        source_indirections.is_empty(),
        "protocol_callbacks uses forbidden source indirection: {source_indirections:?}"
    );
    let imports = production_import_paths(&callbacks);
    let actual = dependency_roots(&callbacks);
    let allowed = [
        "base64",
        "crate",
        "par_term_emu_core_rust",
        "serde_json",
        "std",
        "url",
    ]
    .into_iter()
    .map(str::to_string)
    .collect::<BTreeSet<_>>();
    let disallowed = actual.difference(&allowed).collect::<Vec<_>>();

    assert!(
        disallowed.is_empty(),
        "protocol_callbacks gained dependencies outside its allowlist: {disallowed:?}; all roots: {actual:?}"
    );
    assert!(
        !actual.contains("super"),
        "protocol_callbacks must use capability ports instead of parent session helpers"
    );

    let allowed_import_prefixes = [
        "base64::",
        "crate::model::",
        "par_term_emu_core_rust::terminal::",
        "std::collections::",
    ];
    let disallowed_imports = imports
        .iter()
        .filter(|path| {
            !allowed_import_prefixes
                .iter()
                .any(|prefix| path.starts_with(prefix))
        })
        .collect::<Vec<_>>();
    assert!(
        disallowed_imports.is_empty(),
        "protocol_callbacks imports outside its module allowlist: {disallowed_imports:?}"
    );
    for forbidden in [
        "Terminal",
        "TerminalState",
        "retained_row_for_abs_row",
        "selection_text_for_terminal",
    ] {
        assert!(
            imports
                .iter()
                .all(|path| path.split("::").last() != Some(forbidden)),
            "protocol_callbacks imported forbidden aggregate/helper {forbidden}: {imports:?}"
        );
    }

    let definitions = production_definition_names(&callbacks);
    assert!(definitions.contains("ProtocolHostContext"));
    assert!(definitions.contains("ProtocolEventControl"));
    assert!(definitions.contains("ProtocolTransferControl"));
    assert!(definitions.contains("ProtocolCallbackBatch"));

    let direct_parent_escapes = forbidden_parent_paths(&production_paths(&callbacks));
    assert!(
        direct_parent_escapes.is_empty(),
        "protocol_callbacks reached parent aggregate/helpers through fully-qualified paths: {direct_parent_escapes:?}"
    );

    let host_contract_paths = recursive_type_paths(&callbacks, "ProtocolHostContext");
    let leaked_aggregates = host_contract_paths
        .iter()
        .filter(|path| {
            path.split("::").any(|segment| {
                matches!(
                    segment,
                    "Terminal"
                        | "TerminalState"
                        | "retained_row_for_abs_row"
                        | "selection_text_for_terminal"
                )
            })
        })
        .collect::<Vec<_>>();
    assert!(
        leaked_aggregates.is_empty(),
        "ProtocolHostContext recursive contract leaked terminal aggregates/helpers: {leaked_aggregates:?}"
    );
}

#[test]
fn protocol_host_is_only_the_session_owned_capability_adapter_and_live_drain_facade() {
    let host = parse_rust(&source_path("src/session/protocol_host.rs"));
    let violations = protocol_host_responsibility_violations(&host);
    assert!(
        violations.is_empty(),
        "protocol_host escaped its adapter responsibility: {violations:?}"
    );

    assert_eq!(
        raw_parser_drain_violations(&host),
        vec![
            "terminal.poll_events()",
            "poll_events() in poll_protocol_events"
        ],
        "all raw parser drains must remain isolated in protocol_host"
    );
    assert!(
        production_paths(&host).contains("callback_events_from_parser_events"),
        "protocol_host must immediately map its raw drain into ProtocolCallbackBatch"
    );
}

#[test]
fn adversarial_fixtures_exercise_every_architecture_escape_branch() {
    let path_override = parse_fixture("path_override_escape");
    let path_violations = source_indirection_violations(&path_override);
    assert_eq!(path_violations.len(), 2, "{path_violations:?}");
    assert!(
        path_violations
            .iter()
            .all(|violation| violation.contains("#[path]"))
    );

    let include = parse_fixture("include_escape");
    let include_violations = source_indirection_violations(&include);
    assert_eq!(include_violations.len(), 2, "{include_violations:?}");
    assert!(
        include_violations
            .iter()
            .all(|violation| violation.contains("include!"))
    );

    let raw_drain = parse_fixture("raw_parser_drain_escape");
    assert_eq!(raw_parser_drain_violations(&raw_drain).len(), 3);

    let qualified_parent = parse_fixture("qualified_parent_escape");
    assert!(!forbidden_parent_paths(&production_paths(&qualified_parent)).is_empty());

    fn assert_contract_escape_is_rejected(fixture: &str, escape_kind: &str) {
        let contract = parse_fixture(fixture);
        let paths = recursive_type_paths(&contract, "ProtocolHostContext");
        assert!(
            paths
                .iter()
                .any(|path| path.split("::").any(|segment| segment == "TerminalState")),
            "recursive {escape_kind} escape fixture was not traversed: {paths:?}"
        );
    }
    assert_contract_escape_is_rejected("recursive_supertrait_escape", "supertrait");
    assert_contract_escape_is_rejected("recursive_type_alias_escape", "type-alias");
    assert_contract_escape_is_rejected("recursive_associated_type_escape", "associated-type");

    let block_local_import = parse_fixture("block_local_import_escape");
    assert!(
        production_import_paths(&block_local_import).contains("super::TerminalState"),
        "block-local renamed imports must remain visible to the dependency gate"
    );

    let try_drain = parse_fixture("raw_try_drain_escape");
    assert_eq!(
        raw_parser_drain_violations(&try_drain),
        vec!["terminal.poll_events()"],
        "try-wrapped parser receivers must not evade the raw-drain gate"
    );

    let helper_try_drain = parse_fixture("raw_try_helper_drain_escape");
    assert_eq!(
        raw_parser_drain_violations(&helper_try_drain),
        vec!["poll_events() in drain"],
        "helper-return try receivers must fail closed even without a visible terminal field"
    );

    let broad_host = parse_fixture("protocol_host_responsibility_escape");
    assert!(
        protocol_host_responsibility_violations(&broad_host)
            .iter()
            .any(|violation| violation.contains("handle_osc_payload"))
    );

    let parent_escape = parse_fixture("protocol_host_parent_escape");
    assert!(
        protocol_host_responsibility_violations(&parent_escape)
            .iter()
            .any(|violation| violation.contains("super::parse_hidden_protocol")),
        "protocol_host parent helper escape must fail the exact qualified-path allowlist"
    );
}
