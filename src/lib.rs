use magnus::{define_module, function, method, prelude::*, Error, Ruby};

#[derive(Debug, Clone)]
pub struct Match {
    pub start: usize,
    pub end: usize,
    pub phrase_id: u32,
    pub salience: f32,
    pub count: u32,
    pub n: u8,
}

#[magnus::wrap(class = "PhraseKit::Matcher", free_immediately, size)]
struct Matcher {
    version: String,
}

impl Matcher {
    fn new() -> Self {
        Matcher {
            version: "0.1.0".to_string(),
        }
    }

    fn version(&self) -> String {
        self.version.clone()
    }

    fn hello(&self) -> String {
        "Hello from PhraseKit native extension!".to_string()
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = define_module("PhraseKit")?;
    let class = module.define_class("Matcher", ruby.class_object())?;
    class.define_singleton_method("new", function!(Matcher::new, 0))?;
    class.define_method("version", method!(Matcher::version, 0))?;
    class.define_method("hello", method!(Matcher::hello, 0))?;
    Ok(())
}