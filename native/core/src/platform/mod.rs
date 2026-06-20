pub mod macos;

pub fn default_shell() -> String {
    default_shell_impl()
}

#[cfg(unix)]
fn default_shell_impl() -> String {
    std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string())
}

#[cfg(windows)]
fn default_shell_impl() -> String {
    std::env::var("COMSPEC")
        .or_else(|_| std::env::var("ComSpec"))
        .unwrap_or_else(|_| "powershell.exe".to_string())
}
