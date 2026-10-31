//! Linux platform backends for Snow Apps.
//!
//! Each module owns one platform capability and starts as an `Unsupported`
//! placeholder; the concrete implementation lands with its own milestone task
//! (P3-T1 portal, P3-T2/P5-T2 pipewire, P5-T3 vaapi, P5-T5 v4l2, P5-T6 input,
//! P6-T4 text). Platform-only dependencies must stay in
//! `[target.'cfg(target_os = "linux")'.dependencies]` so consumers on other
//! operating systems never pull them.

pub mod input;
pub mod pipewire;
pub mod portal;
pub mod text;
pub mod v4l2;
pub mod vaapi;
