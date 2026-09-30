pub mod macos;

/// Select the user's login shell, with a fallback available on the target OS.
pub fn default_shell() -> String {
    shell_from_environment(std::env::var("SHELL").ok().as_deref())
}

fn shell_from_environment(shell: Option<&str>) -> String {
    shell
        .filter(|value| !value.is_empty())
        .unwrap_or(if cfg!(target_vendor = "apple") {
            "/bin/zsh"
        } else {
            "/bin/sh"
        })
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::shell_from_environment;

    #[test]
    fn respects_the_configured_shell() {
        assert_eq!(shell_from_environment(Some("/bin/bash")), "/bin/bash");
    }

    #[test]
    fn missing_or_empty_shell_uses_the_platform_fallback() {
        let fallback = if cfg!(target_vendor = "apple") {
            "/bin/zsh"
        } else {
            "/bin/sh"
        };
        assert_eq!(shell_from_environment(None), fallback);
        assert_eq!(shell_from_environment(Some("")), fallback);
    }
}
