#[path = "../tests/fixtures/recording/create.rs"]
mod fixture;

fn main() {
    let path = std::env::args().nth(1).expect("output .trailrec path");
    let frames = std::env::args()
        .nth(2)
        .map(|v| v.parse().expect("positive frame count"))
        .unwrap_or(11);
    assert!(frames > 0);
    fixture::create(std::path::Path::new(&path), frames);
}
