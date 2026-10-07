//! Optional, bounded shell-name evidence. Collected without invoking commands;
//! committed with the owning prompt, never used to authorize a submission.
use std::collections::BTreeSet;

#[derive(Default)]
pub(crate) struct CommandInventory {
    pub(crate) names: Vec<String>,
    pending: Option<Pending>,
}

struct Pending {
    epoch: u64,
    names: BTreeSet<String>,
    bytes: usize,
    complete: bool,
    invalid: bool,
}

impl CommandInventory {
    pub(crate) fn receive(&mut self, fields: &[&str], current: u64) {
        let [kind @ ("commands" | "commands-end"), epoch, tail @ ..] = fields else {
            return;
        };
        let Ok(epoch) = epoch.parse::<u64>() else {
            return;
        };
        if epoch <= current || self.pending.as_ref().is_some_and(|p| epoch < p.epoch) {
            return;
        }
        if self.pending.as_ref().is_none_or(|p| p.epoch != epoch) {
            self.pending = Some(Pending {
                epoch,
                names: BTreeSet::new(),
                bytes: 0,
                complete: false,
                invalid: false,
            });
        }
        let pending = self.pending.as_mut().unwrap();
        if *kind == "commands-end" && tail.is_empty() {
            pending.complete = true;
            return;
        }
        let [chunk] = tail else {
            pending.invalid = true;
            return;
        };
        if pending.invalid || pending.complete {
            pending.invalid = true;
            return;
        }
        pending.bytes += chunk.len();
        if chunk.len() > 4096 || pending.bytes > 65536 {
            pending.invalid = true;
            pending.names.clear();
            return;
        }
        for name in chunk.split(',').filter(|s| !s.is_empty()) {
            if name.len() > 256
                || name
                    .chars()
                    .any(|c| c.is_control() || c.is_whitespace() || c == ';')
            {
                pending.invalid = true;
                pending.names.clear();
                return;
            }
            pending.names.insert(name.into());
            if pending.names.len() > 4096 {
                pending.invalid = true;
                pending.names.clear();
                return;
            }
        }
    }

    pub(crate) fn commit(&mut self, epoch: u64) {
        self.names = self
            .pending
            .take()
            .filter(|p| p.epoch == epoch && p.complete && !p.invalid)
            .map(|p| p.names.into_iter().collect())
            .unwrap_or_default();
    }

    pub(crate) fn clear(&mut self) {
        *self = Self::default();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn names_are_atomic_bounded_and_prompt_scoped() {
        let mut inventory = CommandInventory::default();
        inventory.receive(&["commands", "2", "ls,帮助,deploy"], 1);
        assert!(inventory.names.is_empty());
        inventory.receive(&["commands-end", "2"], 1);
        inventory.commit(2);
        assert!(inventory.names.contains(&"帮助".into()));
        inventory.receive(&["commands", "2", "stale"], 2);
        inventory.commit(3);
        assert!(inventory.names.is_empty());
        inventory.receive(&["commands", "4", "partial"], 3);
        inventory.commit(4);
        assert!(inventory.names.is_empty());
        inventory.receive(&["commands", "5", &"x".repeat(4097)], 4);
        inventory.receive(&["commands-end", "5"], 4);
        inventory.commit(5);
        assert!(inventory.names.is_empty());
        inventory.receive(&["commands", "6", "valid\ninvalid"], 5);
        inventory.receive(&["commands-end", "6"], 5);
        inventory.commit(6);
        assert!(inventory.names.is_empty());
    }
}
