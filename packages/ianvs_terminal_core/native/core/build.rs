fn main() {
    #[cfg(feature = "regenerate-proto")]
    {
        println!("cargo:rerun-if-changed=proto/frame_diff.proto");
        println!("cargo:rerun-if-changed=proto/graphic_asset.proto");
        prost_build::Config::new()
            .out_dir("src/proto")
            .compile_protos(
                &["proto/frame_diff.proto", "proto/graphic_asset.proto"],
                &["proto"],
            )
            .expect("failed to compile runtime protobuf files");
    }
}
