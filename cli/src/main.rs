use std::{env::var, fs, io, path::Path};

const NCI_SRC: Option<&str> = option_env!("NCI_SRC");
const HELP: &str = r#"
show <source url> -> run `nix flake show` the specified source
build <source url> <package: default package> -> builds a package (defaults to the default package) in the specified source
run <source url> <app: default app> -> run an app (defaults to the default app) in the specified source
metadata <source url> -> show metadata of specified source
update <source url> -> update the specified source
fetch <git url> <location: current dir> -> fetch a source to the specified location and generate a flake file
"#;

fn main() -> io::Result<()> {
    let sources = var("HOME").ok().as_deref().map_or_else(
        || Path::new("sources").to_path_buf(),
        |home| Path::new(home).join(".cache/nci-sources"),
    );

    if let Some(cmd) = arg::get(1) {
        let run_url = |cmds: &[&str], suffix: &str| -> io::Result<()> {
            let url = arg::get(2);

            if let Some(url) = url {
                let source_dir = sources.join(url.replace(|c| [':', '/', '.'].contains(&c), "_"));
                fs::create_dir_all(&source_dir)?;
                let flake = util::craft_flake(&url);
                println!("+write flake to {}", source_dir.to_string_lossy());
                fs::write(source_dir.join("flake.nix"), flake.into_bytes())?;
                let mut args = Vec::with_capacity(cmds.len() + 1);
                args.extend(cmds);
                let flake_path = format!("{}{}", source_dir.to_string_lossy(), suffix);
                args.push(flake_path.as_ref());
                cmd::nix(args)?;
            } else {
                println!("please enter a source url (eg. `github:owner/repo`)");
            }

            Ok(())
        };

        let cmd_frag = |cmd| {
            let frag = arg::get(3).map(|frag| format!("#{}", frag));
            run_url(&[cmd], frag.as_deref().unwrap_or(""))
        };

        let cmd = cmd.as_str();
        match cmd {
            "show" | "metadata" => run_url(&["flake", cmd], "")?,
            "run" => cmd_frag(cmd)?,
            "build" => cmd_frag(cmd)?,
            "update" => run_url(&["flake", "lock", "--update-input", "source"], "")?,
            _ => println!("{}", HELP),
        }
    } else {
        println!("{}", HELP)
    }

    Ok(())
}

mod util {
    use super::NCI_SRC;

    pub(super) fn craft_flake(source: &str) -> String {
        include_str!("flk.nix")
            .replace("source_url", source)
            .replace("nci_source", NCI_SRC.unwrap())
    }
}

mod arg {
    use std::env::args;

    pub(super) fn get(n: usize) -> Option<String> {
        args().nth(n)
    }

    #[allow(dead_code)]
    pub(super) fn flag_value(pred: fn(&str) -> bool) -> Option<String> {
        args().skip_while(|arg| !pred(arg)).nth(1)
    }
}

mod cmd {
    use std::{io, process::Command};

    #[allow(dead_code)]
    pub(super) fn git<'a>(args: impl AsRef<[&'a str]>) -> io::Result<i32> {
        let mut nix_args = vec!["shell", "nixpkgs#git", "-c", "git"];
        nix_args.extend(args.as_ref());
        nix(nix_args)
    }

    pub(super) fn nix<'a>(args: impl AsRef<[&'a str]>) -> io::Result<i32> {
        run("nix", args)
    }

    pub(super) fn run<'a>(cmd: &str, args: impl AsRef<[&'a str]>) -> io::Result<i32> {
        println!(
            "+{}{}",
            cmd,
            args.as_ref().iter().fold(String::new(), |mut tot, item| {
                tot.push(' ');
                tot.push_str(item);
                tot
            })
        );
        Command::new(cmd)
            .args(args.as_ref())
            .spawn()?
            .wait()
            .map(|exit| exit.code().unwrap_or_default())
    }
}
