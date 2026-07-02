fn main() {
    #[cfg(feature = "regenerate-proto")]
    {
        println!("cargo:rerun-if-changed=proto/frame_diff.proto");
        prost_build::Config::new()
            .out_dir("src/proto")
            .compile_protos(&["proto/frame_diff.proto"], &["proto"])
            .expect("failed to compile frame_diff.proto");
    }
}
