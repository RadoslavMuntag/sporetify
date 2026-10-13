//! Sporetify daemon library. `main.rs` wires these modules to a socket;
//! integration tests drive them directly.

pub mod art;
pub mod auth;
pub mod catalog;
pub mod ipc;
pub mod mpris;
pub mod ops;
pub mod persist;
pub mod player;
pub mod private;
pub mod proto;
pub mod state;
