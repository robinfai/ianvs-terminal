use std::env;
use std::path::PathBuf;

fn main() {
    let output = env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .expect("usage: generate_c_header <output-path>");
    let crate_directory = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    cbindgen::Builder::new()
        .with_crate(crate_directory)
        .with_language(cbindgen::Language::C)
        .with_include_guard("IANVS_CORE_H")
        .generate()
        .expect("generate ianvs_core C header")
        .write_to_file(output);
}
