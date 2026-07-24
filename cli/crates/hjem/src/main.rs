fn main() {
  if let Err(err) = hjem_core::run() {
    eprintln!("{err}");
    std::process::exit(1);
  }
}
