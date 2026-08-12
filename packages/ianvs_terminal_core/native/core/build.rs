fn main() {
    #[cfg(feature = "regenerate-proto")]
    {
        use std::path::PathBuf;

        println!("cargo:rerun-if-changed=proto/frame_diff.proto");
        println!("cargo:rerun-if-changed=proto/graphic_asset.proto");
        println!("cargo:rerun-if-env-changed=IANVS_PROTO_OUT_DIR");
        let output_directory = std::env::var_os("IANVS_PROTO_OUT_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("src/proto"));
        std::fs::create_dir_all(&output_directory)
            .expect("create runtime protobuf output directory");
        prost_build::Config::new()
            .out_dir(output_directory)
            .compile_protos(
                &["proto/frame_diff.proto", "proto/graphic_asset.proto"],
                &["proto"],
            )
            .expect("failed to compile runtime protobuf files");
    }
}
