fn main() {
  tracing_subscriber::fmt()
    .compact()
    .without_time()
    .with_target(false)
    .with_max_level(hjem_core::diagnostic_level())
    .init();

  if let Err(err) = hjem_core::run() {
    tracing::error!(error = %err, "hjem failed");
    std::process::exit(1);
  }
}
