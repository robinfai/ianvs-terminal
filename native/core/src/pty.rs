use crate::model::{TerminalEmulation, TerminalProfile};
use portable_pty::{CommandBuilder, MasterPty, PtySize, native_pty_system};
use std::io::{Read, Write};

pub struct PtyRuntime {
    pub master: Box<dyn MasterPty + Send>,
    pub reader: Box<dyn Read + Send>,
    pub writer: Box<dyn Write + Send>,
    pub child: Box<dyn portable_pty::Child + Send + Sync>,
}

pub fn spawn_pty(profile: &TerminalProfile, rows: u16, cols: u16) -> anyhow::Result<PtyRuntime> {
    let pty_system = native_pty_system();
    let pair = pty_system.openpty(PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    })?;

    let shell = if profile.launch.program.is_empty() {
        crate::platform::macos::default_shell()
    } else {
        profile.launch.program.clone()
    };

    let mut command = CommandBuilder::new(shell);
    for arg in &profile.launch.args {
        command.arg(arg);
    }
    if let Some(cwd) = &profile.launch.cwd {
        command.cwd(cwd);
    }
    for (key, value) in &profile.launch.env {
        command.env(key, value);
    }
    match profile.terminal.emulation {
        TerminalEmulation::Xterm256 => {
            command.env("TERM", "xterm-256color");
            command.env("COLORTERM", "truecolor");
        }
        TerminalEmulation::Vt220 => {
            command.env("TERM", "vt220");
            command.env_remove("COLORTERM");
        }
    }

    let child = pair.slave.spawn_command(command)?;
    let reader = pair.master.try_clone_reader()?;
    let writer = pair.master.take_writer()?;

    Ok(PtyRuntime {
        master: pair.master,
        reader,
        writer,
        child,
    })
}
