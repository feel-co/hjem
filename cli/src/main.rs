use chrono::{DateTime, NaiveDate, Utc};
use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use smfh_core::manifest::{File, FileKind, Manifest};
use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::Command as ProcCommand;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Parser, Debug)]
#[command(version, about = "Hjem standalone CLI")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    Standalone {
        #[command(subcommand)]
        command: StandaloneCommand,
    },
    Internal {
        #[command(subcommand)]
        command: InternalCommand,
    },
    Manifest {
        #[command(subcommand)]
        command: ManifestCommand,
    },
    Activate {
        #[arg(long)]
        manifest: PathBuf,
        #[arg(long)]
        state: PathBuf,
        #[arg(long, default_value = ".backup-")]
        prefix: String,
        #[arg(long, default_value_t = false)]
        impure: bool,
        #[arg(long, default_value_t = false)]
        json: bool,
    },
}

#[derive(Subcommand, Debug)]
enum ManifestCommand {
    Validate {
        #[arg(long)]
        manifest: PathBuf,
        #[arg(long, default_value_t = false)]
        impure: bool,
        #[arg(long, default_value_t = false)]
        json: bool,
    },
    Diff {
        #[arg(long = "new")]
        new_manifest: PathBuf,
        #[arg(long = "old")]
        old_manifest: PathBuf,
        #[arg(long, default_value_t = false)]
        impure: bool,
        #[arg(long, default_value_t = false)]
        json: bool,
    },
}

#[derive(Subcommand, Debug)]
enum InternalCommand {
    ValidateManifest {
        #[arg(long)]
        manifest: PathBuf,
        #[arg(long, default_value_t = false)]
        impure: bool,
        #[arg(long, default_value_t = false)]
        json: bool,
    },
    Activate {
        #[arg(long)]
        manifest: PathBuf,
        #[arg(long)]
        state: PathBuf,
        #[arg(long)]
        actions_file: Option<PathBuf>,
        #[arg(long, default_value = ".backup-")]
        prefix: String,
        #[arg(long, default_value_t = false)]
        impure: bool,
        #[arg(long)]
        external_linker: Option<PathBuf>,
        #[arg(long = "linker-arg")]
        linker_args: Vec<String>,
        #[arg(long, default_value_t = false)]
        json: bool,
    },
    ReloadActions {
        #[arg(long)]
        actions_file: PathBuf,
        #[arg(long)]
        user: String,
        #[arg(long, default_value_t = false)]
        require_running_systemd: bool,
        #[arg(long, default_value_t = false)]
        json: bool,
    },
    CleanupState {
        #[arg(long)]
        state_dir: PathBuf,
        #[arg(long = "enabled-user")]
        enabled_users: Vec<String>,
        #[arg(long, default_value_t = false)]
        json: bool,
    },
}

#[derive(Subcommand, Debug)]
enum StandaloneCommand {
    Init {
        #[arg(long)]
        dir: Option<PathBuf>,
        #[arg(long, default_value_t = false)]
        no_flake: bool,
        #[arg(long, default_value_t = false)]
        switch: bool,
    },
    Switch {
        #[arg(long)]
        manifest: Option<PathBuf>,
        #[arg(long)]
        config: Option<PathBuf>,
        #[arg(long)]
        flake: Option<String>,
        #[arg(long)]
        flake_attr: Option<String>,
        #[arg(long)]
        state_dir: Option<PathBuf>,
        #[arg(long, default_value_t = false)]
        rollback: bool,
        #[arg(long)]
        external_linker: Option<PathBuf>,
        #[arg(long = "linker-arg")]
        linker_args: Vec<String>,
        #[arg(long, default_value = ".backup-")]
        prefix: String,
        #[arg(long, default_value_t = false)]
        impure: bool,
    },
    Build {
        #[arg(long)]
        manifest: Option<PathBuf>,
        #[arg(long)]
        config: Option<PathBuf>,
        #[arg(long)]
        flake: Option<String>,
        #[arg(long)]
        flake_attr: Option<String>,
        #[arg(long)]
        state_dir: Option<PathBuf>,
        #[arg(long, default_value_t = false)]
        impure: bool,
    },
    Generations {
        #[arg(long)]
        state_dir: Option<PathBuf>,
    },
    RemoveGenerations {
        ids: Vec<String>,
        #[arg(long)]
        state_dir: Option<PathBuf>,
    },
    Rollback {
        #[arg(long)]
        state_dir: Option<PathBuf>,
        #[arg(long)]
        generation: Option<String>,
        #[arg(long)]
        external_linker: Option<PathBuf>,
        #[arg(long = "linker-arg")]
        linker_args: Vec<String>,
        #[arg(long, default_value = ".backup-")]
        prefix: String,
        #[arg(long, default_value_t = false)]
        impure: bool,
    },
    ExpireGenerations {
        timestamp: String,
        #[arg(long)]
        state_dir: Option<PathBuf>,
    },
}

#[derive(Serialize, Deserialize, Clone)]
struct TriggerAction {
    action: String,
    unit: String,
    reason: String,
}

#[derive(Serialize, Deserialize)]
struct ActivateResult {
    mode: String,
    actions: Vec<TriggerAction>,
}

#[derive(Serialize)]
struct ValidateResult {
    ok: bool,
    file_count: usize,
    version: u64,
}

#[derive(Serialize)]
struct DiffResult {
    ok: bool,
    changed: bool,
}

#[derive(Serialize)]
struct CleanupResult {
    removed: Vec<String>,
}

#[derive(Serialize)]
struct ReloadResult {
    skipped: bool,
    reason: Option<String>,
    applied: usize,
}

fn main() {
    let cli = Cli::parse();
    let result = match cli.command {
        Command::Manifest { command } => run_manifest(command),
        Command::Activate {
            manifest,
            state,
            prefix,
            impure,
            json,
        } => run_activate_internal(ActivateArgs {
            manifest,
            state,
            actions_file: None,
            prefix,
            impure,
            external_linker: None,
            linker_args: Vec::new(),
            json,
        }),
        Command::Internal { command } => run_internal(command),
        Command::Standalone { command } => run_standalone(command),
    };

    if let Err(err) = result {
        eprintln!("{err}");
        std::process::exit(1);
    }
}

fn run_manifest(command: ManifestCommand) -> Result<(), String> {
    match command {
        ManifestCommand::Validate {
            manifest,
            impure,
            json,
        } => {
            let m = read_verified(&manifest, impure)?;
            if json {
                print_json(&ValidateResult {
                    ok: true,
                    file_count: m.files.len(),
                    version: m.version,
                })?;
            } else {
                println!("ok");
            }
            Ok(())
        }
        ManifestCommand::Diff {
            new_manifest,
            old_manifest,
            impure,
            json,
        } => {
            let current = read_verified(&new_manifest, impure)?;
            let changed = !manifests_equivalent(&current, &old_manifest, impure)?;
            if json {
                print_json(&DiffResult { ok: true, changed })?;
            } else if changed {
                println!("changed");
            } else {
                println!("unchanged");
            }
            Ok(())
        }
    }
}

fn run_internal(command: InternalCommand) -> Result<(), String> {
    match command {
        InternalCommand::ValidateManifest {
            manifest,
            impure,
            json,
        } => {
            let m = read_verified(&manifest, impure)?;
            if json {
                print_json(&ValidateResult {
                    ok: true,
                    file_count: m.files.len(),
                    version: m.version,
                })?;
            }
            Ok(())
        }
        InternalCommand::Activate {
            manifest,
            state,
            actions_file,
            prefix,
            impure,
            external_linker,
            linker_args,
            json,
        } => run_activate_internal(ActivateArgs {
            manifest,
            state,
            actions_file,
            prefix,
            impure,
            external_linker,
            linker_args,
            json,
        }),
        InternalCommand::ReloadActions {
            actions_file,
            user,
            require_running_systemd,
            json,
        } => run_reload_actions(&actions_file, &user, require_running_systemd, json),
        InternalCommand::CleanupState {
            state_dir,
            enabled_users,
            json,
        } => run_cleanup_state(&state_dir, &enabled_users, json),
    }
}

fn run_standalone(command: StandaloneCommand) -> Result<(), String> {
    match command {
        StandaloneCommand::Init {
            dir,
            no_flake,
            switch,
        } => {
            let conf_dir = standalone_config_dir(dir)?;
            fs::create_dir_all(&conf_dir).map_err(|e| e.to_string())?;

            let home_nix = conf_dir.join("hjem.nix");
            let mut created_files = Vec::new();
            if !home_nix.exists() {
                fs::write(
                    &home_nix,
                    format!(
                        "{{\n  version = 3;\n  files = [\n    {{\n      type = \"symlink\";\n      source = ./dotfiles/example;\n      target = \"{}/.config/example\";\n    }}\n  ];\n}}\n",
                        home_dir()?.display()
                    ),
                )
                .map_err(|e| e.to_string())?;
                created_files.push(home_nix.clone());
            }

            if !no_flake {
                let flake_nix = conf_dir.join("flake.nix");
                if !flake_nix.exists() {
                    let user = std::env::var("USER").unwrap_or_else(|_| "user".to_string());
                    fs::write(
                        &flake_nix,
                        format!(
                            "{{\n  description = \"Hjem standalone configuration\";\n\n  outputs = {{ self }}: {{\n    hjemConfigurations.\"{user}\".manifest = import ./hjem.nix;\n  }};\n}}\n"
                        ),
                    )
                    .map_err(|e| e.to_string())?;
                    created_files.push(flake_nix);
                }
            }

            println!("Initialized Hjem standalone config in {}", conf_dir.display());
            if created_files.is_empty() {
                println!("No new files were created (existing config kept as-is).");
            } else {
                for path in created_files {
                    println!("Created {}", path.display());
                }
            }
            if no_flake {
                println!(
                    "Next step: hjem standalone switch --config {}",
                    home_nix.display()
                );
            } else {
                println!("Next step: hjem standalone switch --flake {}", conf_dir.display());
            }

            if switch {
                println!("Applying initial generation...");
                let source = if no_flake {
                    StandaloneSource::Config(home_nix)
                } else {
                    StandaloneSource::Flake(conf_dir)
                };
                standalone_switch_from_source(
                    source,
                    None,
                    None,
                    Vec::new(),
                    ".backup-".to_string(),
                    false,
                )?;
                println!("Initial generation applied.");
            }

            Ok(())
        }
        StandaloneCommand::Switch {
            manifest,
            config,
            flake,
            flake_attr,
            state_dir,
            rollback,
            external_linker,
            linker_args,
            prefix,
            impure,
        } => {
            if rollback {
                let set_count = usize::from(manifest.is_some())
                    + usize::from(config.is_some())
                    + usize::from(flake.is_some())
                    + usize::from(flake_attr.is_some());
                if set_count != 0 {
                    return Err(
                        "--rollback cannot be combined with --manifest/--config/--flake/--flake-attr"
                            .to_string(),
                    );
                }
                standalone_switch_rollback(
                    state_dir,
                    external_linker,
                    linker_args,
                    prefix,
                    impure,
                )?;
            } else {
                let manifest =
                    resolve_manifest_input(manifest, config, flake, flake_attr.clone(), impure)?;
                let source = if let Some(path) = manifest._resolved_from_manifest {
                    StandaloneSource::Manifest(path)
                } else if let Some(path) = manifest._resolved_from_config {
                    StandaloneSource::Config(path)
                } else if let Some(flake_ref) = manifest._resolved_from_flake {
                    StandaloneSource::FlakeWithAttr(flake_ref, flake_attr)
                } else {
                    StandaloneSource::Manifest(manifest.path)
                };
                standalone_switch_from_source(
                    source,
                    state_dir,
                    external_linker,
                    linker_args,
                    prefix,
                    impure,
                )?;
            }
            Ok(())
        }
        StandaloneCommand::Build {
            manifest,
            config,
            flake,
            flake_attr,
            state_dir,
            impure,
        } => {
            let manifest = resolve_manifest_input(manifest, config, flake, flake_attr, impure)?;
            let _ = read_verified(&manifest.path, impure)?;
            let base = standalone_state_dir(state_dir)?;
            let builds = base.join("builds");
            fs::create_dir_all(&builds).map_err(|e| e.to_string())?;
            let build_id = now_id("build");
            atomic_copy(&manifest.path, &builds.join(format!("{build_id}.json")))?;
            println!("Build recorded: {build_id}");
            Ok(())
        }
        StandaloneCommand::Generations { state_dir } => {
            let base = standalone_state_dir(state_dir)?;
            let gens = list_generations(&base)?;
            if gens.is_empty() {
                println!("No generations found in {}", base.join("generations").display());
                return Ok(());
            }
            for g in gens {
                println!("{}", g.display());
            }
            Ok(())
        }
        StandaloneCommand::RemoveGenerations { ids, state_dir } => {
            if ids.is_empty() {
                return Err("remove-generations expects at least one generation id".to_string());
            }
            let base = standalone_state_dir(state_dir)?;
            let mut removed = 0usize;
            for id in ids {
                let path = base.join("generations").join(&id);
                if path.exists() {
                    fs::remove_dir_all(&path).map_err(|e| e.to_string())?;
                    removed += 1;
                }
            }
            println!("Removed {removed} generation(s).");
            Ok(())
        }
        StandaloneCommand::Rollback {
            state_dir,
            generation,
            external_linker,
            linker_args,
            prefix,
            impure,
        } => {
            let base = standalone_state_dir(state_dir)?;
            let target = resolve_generation_manifest(&base, generation.as_deref())?;
            let target_id = target
                .parent()
                .and_then(generation_id_from_path)
                .ok_or_else(|| "Failed to determine generation id".to_string())?;
            let state = base.join("current").join("manifest.json");
            run_activate_internal(ActivateArgs {
                manifest: target.clone(),
                state,
                actions_file: Some(base.join("current").join("actions.json")),
                prefix,
                impure,
                external_linker,
                linker_args,
                json: false,
            })?;
            set_current_generation_id(&base, &target_id)?;
            println!("Rolled back to generation {target_id}");
            Ok(())
        }
        StandaloneCommand::ExpireGenerations {
            timestamp,
            state_dir,
        } => {
            let base = standalone_state_dir(state_dir)?;
            let mut gens = list_generations(&base)?;
            let cutoff = parse_expire_timestamp(&timestamp)?;
            let current = read_current_generation_id(&base)?;
            let mut removed = 0usize;

            for path in gens.drain(..) {
                let Some(id) = generation_id_from_path(&path) else {
                    continue;
                };
                if current.as_deref() == Some(id.as_str()) {
                    continue;
                }
                let Some(gen_ts) = generation_timestamp_from_id(&id) else {
                    continue;
                };
                if gen_ts <= cutoff {
                    fs::remove_dir_all(path).map_err(|e| e.to_string())?;
                    removed += 1;
                }
            }
            println!("Expired {removed} generation(s).");
            Ok(())
        }
    }
}

struct ResolvedManifest {
    path: PathBuf,
    _temp_dir: Option<PathBuf>,
    _resolved_from_manifest: Option<PathBuf>,
    _resolved_from_config: Option<PathBuf>,
    _resolved_from_flake: Option<String>,
}

enum StandaloneSource {
    Manifest(PathBuf),
    Config(PathBuf),
    Flake(PathBuf),
    FlakeWithAttr(String, Option<String>),
}

fn resolve_manifest_input(
    manifest: Option<PathBuf>,
    config: Option<PathBuf>,
    flake: Option<String>,
    flake_attr: Option<String>,
    impure: bool,
) -> Result<ResolvedManifest, String> {
    let set_count = usize::from(manifest.is_some())
        + usize::from(config.is_some())
        + usize::from(flake.is_some());
    if set_count != 1 {
        return Err(
            "Provide exactly one of --manifest, --config, or --flake for standalone commands"
                .to_string(),
        );
    }

    if let Some(path) = manifest.clone() {
        return Ok(ResolvedManifest {
            path,
            _temp_dir: None,
            _resolved_from_manifest: manifest,
            _resolved_from_config: None,
            _resolved_from_flake: None,
        });
    }

    let json = if let Some(config_path) = config.as_ref() {
        eval_nix_config(config_path, impure)?
    } else if let Some(flake_ref) = flake.as_ref() {
        eval_nix_flake(flake_ref, flake_attr.as_deref(), impure)?
    } else {
        return Err("No manifest source was provided".to_string());
    };

    let manifest_json = extract_manifest_json(json)?;
    let temp_dir = mk_temp_dir("hjem-manifest-eval")?;
    let manifest_path = temp_dir.join("manifest.json");
    fs::write(
        &manifest_path,
        serde_json::to_vec_pretty(&manifest_json).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;

    Ok(ResolvedManifest {
        path: manifest_path,
        _temp_dir: Some(temp_dir),
        _resolved_from_manifest: None,
        _resolved_from_config: config,
        _resolved_from_flake: flake,
    })
}

fn standalone_switch_from_source(
    source: StandaloneSource,
    state_dir: Option<PathBuf>,
    external_linker: Option<PathBuf>,
    linker_args: Vec<String>,
    prefix: String,
    impure: bool,
) -> Result<(), String> {
    println!("Evaluating standalone input...");
    let (manifest, source_ref) = match source {
        StandaloneSource::Manifest(path) => (
            resolve_manifest_input(Some(path.clone()), None, None, None, impure)?,
            StandaloneSource::Manifest(path),
        ),
        StandaloneSource::Config(path) => (
            resolve_manifest_input(None, Some(path.clone()), None, None, impure)?,
            StandaloneSource::Config(path),
        ),
        StandaloneSource::Flake(path) => {
            let flake_ref = path
                .to_str()
                .ok_or_else(|| "Invalid flake path".to_string())?
                .to_string();
            (
                resolve_manifest_input(None, None, Some(flake_ref.clone()), None, impure)?,
                StandaloneSource::Flake(path),
            )
        }
        StandaloneSource::FlakeWithAttr(flake_ref, flake_attr) => (
            resolve_manifest_input(
                None,
                None,
                Some(flake_ref.clone()),
                flake_attr.clone(),
                impure,
            )?,
            StandaloneSource::FlakeWithAttr(flake_ref, flake_attr),
        ),
    };

    let base = standalone_state_dir(state_dir)?;
    println!("Applying manifest...");
    let state = base.join("current").join("manifest.json");
    let actions_file = base.join("current").join("actions.json");
    run_activate_internal(ActivateArgs {
        manifest: manifest.path.clone(),
        state,
        actions_file: Some(actions_file),
        prefix,
        impure,
        external_linker,
        linker_args,
        json: false,
    })?;

    let generation_id = record_generation(&base, &manifest.path)?;
    write_last_source(&base, &source_ref)?;
    set_current_generation_id(&base, &generation_id)?;
    println!("Activated generation {generation_id}");
    Ok(())
}

fn standalone_switch_rollback(
    state_dir: Option<PathBuf>,
    external_linker: Option<PathBuf>,
    linker_args: Vec<String>,
    prefix: String,
    impure: bool,
) -> Result<(), String> {
    let base = standalone_state_dir(state_dir)?;
    let target_id = previous_generation_id(&base)?;
    println!("Rolling back to generation {target_id}...");
    let target_manifest = base
        .join("generations")
        .join(&target_id)
        .join("manifest.json");
    if !target_manifest.exists() {
        return Err(format!(
            "Generation manifest missing: {}",
            target_manifest.display()
        ));
    }

    let state = base.join("current").join("manifest.json");
    run_activate_internal(ActivateArgs {
        manifest: target_manifest,
        state,
        actions_file: Some(base.join("current").join("actions.json")),
        prefix,
        impure,
        external_linker,
        linker_args,
        json: false,
    })?;
    set_current_generation_id(&base, &target_id)?;
    Ok(())
}

fn eval_nix_config(config_path: &Path, impure: bool) -> Result<Value, String> {
    let mut cmd = ProcCommand::new("nix");
    cmd.arg("eval").arg("--json").arg("--file").arg(config_path);
    if impure {
        cmd.arg("--impure");
    }
    let output = cmd.output().map_err(|e| {
        format!(
            "failed to execute 'nix eval' for config '{}': {e}. Ensure Nix is installed and available in PATH",
            config_path.display()
        )
    })?;
    if !output.status.success() {
        return Err(format!(
            "nix eval failed for config '{}': {}\nHint: ensure the file evaluates to a manifest value or {{ manifest = ...; }} and pass --impure if your expression needs impure builtins",
            config_path.display(),
            String::from_utf8_lossy(&output.stderr)
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|e| e.to_string())
}

fn eval_nix_flake(
    flake_ref: &str,
    flake_attr: Option<&str>,
    impure: bool,
) -> Result<Value, String> {
    let user = std::env::var("USER").unwrap_or_else(|_| "default".to_string());
    let attr = flake_attr
        .map(str::to_string)
        .unwrap_or_else(|| format!("hjemConfigurations.\"{user}\".manifest"));
    let full_ref = format!("{flake_ref}#{attr}");
    let mut cmd = ProcCommand::new("nix");
    cmd.arg("eval").arg("--json").arg(full_ref);
    if impure {
        cmd.arg("--impure");
    }
    let output = cmd.output().map_err(|e| {
        format!(
            "failed to execute 'nix eval' for flake '{flake_ref}': {e}. Ensure Nix is installed and available in PATH"
        )
    })?;
    if !output.status.success() {
        return Err(format!(
            "nix eval failed for flake '{}': {}\nHint: verify the flake output attr '{}' exists and evaluates to a manifest",
            flake_ref,
            String::from_utf8_lossy(&output.stderr),
            attr
        ));
    }
    serde_json::from_slice(&output.stdout).map_err(|e| {
        format!(
            "nix eval output for flake '{}' was not valid JSON: {e}",
            flake_ref
        )
    })
}

fn extract_manifest_json(value: Value) -> Result<Value, String> {
    if value.get("version").is_some() && value.get("files").is_some() {
        return Ok(value);
    }
    if let Some(manifest) = value.get("manifest") {
        return Ok(manifest.clone());
    }
    Err(
        "evaluated Nix value is not a manifest.\nExpected either:\n  1) { version = 3; files = [ ... ]; }\n  2) { manifest = { version = 3; files = [ ... ]; }; }"
            .to_string(),
    )
}

fn mk_temp_dir(prefix: &str) -> Result<PathBuf, String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("{prefix}-{}-{now}", std::process::id()));
    fs::create_dir_all(&dir).map_err(|e| {
        format!(
            "failed to create temporary directory '{}': {e}",
            dir.display()
        )
    })?;
    Ok(dir)
}

struct ActivateArgs {
    manifest: PathBuf,
    state: PathBuf,
    actions_file: Option<PathBuf>,
    prefix: String,
    impure: bool,
    external_linker: Option<PathBuf>,
    linker_args: Vec<String>,
    json: bool,
}

fn run_activate_internal(args: ActivateArgs) -> Result<(), String> {
    let new_manifest_for_apply = read_verified(&args.manifest, args.impure)?;
    let new_manifest_for_diff = read_verified(&args.manifest, args.impure)?;
    let had_state = args.state.exists();

    let actions = if had_state {
        let old_manifest = read_verified(&args.state, args.impure)?;
        trigger_actions(&old_manifest, &new_manifest_for_diff)
    } else {
        Vec::new()
    };

    if let Some(linker) = args.external_linker {
        run_external_linker(
            &linker,
            &args.linker_args,
            &args.manifest,
            &args.state,
            had_state,
        )?;
    } else {
        new_manifest_for_apply
            .diff(&args.state, &args.prefix, true)
            .map_err(|e| format!("built-in linker activation failed: {e}"))?;
    }

    atomic_copy(&args.manifest, &args.state)?;

    let result = ActivateResult {
        mode: if had_state {
            "incremental".to_string()
        } else {
            "first".to_string()
        },
        actions,
    };

    if let Some(actions_file) = args.actions_file {
        if let Some(parent) = actions_file.parent() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        fs::write(
            actions_file,
            serde_json::to_string_pretty(&result).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
    }

    if args.json {
        print_json(&result)?;
    } else {
        println!("mode={}", result.mode);
    }

    Ok(())
}

fn run_external_linker(
    linker: &Path,
    linker_args: &[String],
    new_manifest: &Path,
    old_manifest: &Path,
    had_state: bool,
) -> Result<(), String> {
    println!("Using external linker: {}", linker.display());
    let mut cmd = ProcCommand::new(linker);
    for arg in linker_args {
        cmd.arg(arg);
    }

    if had_state {
        cmd.arg("diff").arg(new_manifest).arg(old_manifest);
    } else {
        cmd.arg("activate").arg(new_manifest);
    }

    let status = cmd.status().map_err(|e| {
        format!(
            "failed to execute external linker '{}': {e}",
            linker.display()
        )
    })?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "external linker '{}' failed with status {}",
            linker.display(),
            status
        ))
    }
}

fn run_reload_actions(
    actions_file: &Path,
    user: &str,
    require_running_systemd: bool,
    json: bool,
) -> Result<(), String> {
    if require_running_systemd {
        let status = ProcCommand::new("systemctl")
            .args(["--user", "is-system-running"])
            .output()
            .map_err(|e| format!("failed to query systemd user status: {e}"))?;

        let running = String::from_utf8_lossy(&status.stdout).trim().to_string();
        if !(running == "running" || running == "degraded") {
            let res = ReloadResult {
                skipped: true,
                reason: Some(format!(
                    "User systemd for {user} is not running (status: {running})"
                )),
                applied: 0,
            };
            if json {
                print_json(&res)?;
            } else if let Some(reason) = res.reason {
                println!("{reason}");
            }
            return Ok(());
        }
    }

    let daemon_reload = ProcCommand::new("systemctl")
        .args(["--user", "daemon-reload"])
        .status()
        .map_err(|e| format!("failed to run systemctl --user daemon-reload: {e}"))?;
    if !daemon_reload.success() {
        return Err("systemctl --user daemon-reload failed".to_string());
    }

    if !actions_file.exists() {
        let res = ReloadResult {
            skipped: true,
            reason: Some(format!("No activation metadata for {user}; skipping.")),
            applied: 0,
        };
        if json {
            print_json(&res)?;
        }
        return Ok(());
    }

    let parsed: ActivateResult =
        serde_json::from_slice(&fs::read(actions_file).map_err(|e| e.to_string())?)
            .map_err(|e| format!("failed to parse actions file '{}': {e}", actions_file.display()))?;

    let mut applied = 0usize;
    for action in parsed.actions {
        let mut cmd = ProcCommand::new("systemctl");
        cmd.arg("--user");
        match action.action.as_str() {
            "restart" => {
                cmd.arg("try-restart").arg(&action.unit);
            }
            "reload" => {
                cmd.arg("reload-or-try-restart").arg(&action.unit);
            }
            _ => {
                continue;
            }
        }

        let status = cmd.status().map_err(|e| e.to_string())?;
        if !status.success() {
            eprintln!(
                "Warning: action {} failed for {}",
                action.action, action.unit
            );
        }
        applied += 1;
    }

    if json {
        print_json(&ReloadResult {
            skipped: false,
            reason: None,
            applied,
        })?;
    }

    Ok(())
}

fn run_cleanup_state(state_dir: &Path, enabled_users: &[String], json: bool) -> Result<(), String> {
    fs::create_dir_all(state_dir).map_err(|e| e.to_string())?;

    let enabled: BTreeSet<&str> = enabled_users.iter().map(String::as_str).collect();
    let mut removed = Vec::new();

    for entry in fs::read_dir(state_dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let file_name = entry.file_name();
        let file_name = file_name.to_string_lossy();

        let user = file_name
            .strip_prefix("manifest-")
            .and_then(|s| s.strip_suffix(".json"))
            .or_else(|| {
                file_name
                    .strip_prefix("actions-")
                    .and_then(|s| s.strip_suffix(".json"))
            });

        if let Some(user) = user {
            if !enabled.contains(user) {
                fs::remove_file(entry.path()).map_err(|e| e.to_string())?;
                removed.push(file_name.to_string());
            }
        }
    }

    if json {
        print_json(&CleanupResult { removed })?;
    }

    Ok(())
}

fn read_verified(path: &Path, impure: bool) -> Result<Manifest, String> {
    let manifest = Manifest::read(path, impure)
        .map_err(|e| format!("failed to read manifest '{}': {e}", path.display()))?;
    let violations = manifest.verify();
    if violations.is_empty() {
        Ok(manifest)
    } else {
        let errors = violations
            .iter()
            .map(std::string::ToString::to_string)
            .collect::<Vec<_>>()
            .join("\n");
        Err(format!("manifest '{}' failed validation:\n{errors}", path.display()))
    }
}

fn manifests_equivalent(
    new_manifest: &Manifest,
    old_path: &Path,
    impure: bool,
) -> Result<bool, String> {
    if !old_path.exists() {
        return Ok(false);
    }
    let old_manifest = read_verified(old_path, impure)?;

    let mut old_files = old_manifest.files.clone();
    let mut new_files = new_manifest.files.clone();

    old_files.sort_by(file_sort_key);
    new_files.sort_by(file_sort_key);

    Ok(old_files == new_files)
}

fn file_sort_key(a: &File, b: &File) -> std::cmp::Ordering {
    a.target
        .cmp(&b.target)
        .then_with(|| a.kind.to_string().cmp(&b.kind.to_string()))
        .then_with(|| a.source.cmp(&b.source))
}

fn trigger_actions(old_manifest: &Manifest, new_manifest: &Manifest) -> Vec<TriggerAction> {
    let old_units = unit_sources(old_manifest);
    let new_units = unit_sources(new_manifest);
    let mut actions = Vec::new();

    for (unit, new_source) in &new_units {
        let Some(old_source) = old_units.get(unit) else {
            continue;
        };

        let old_restart = trigger_value(old_source, "X-Restart-Triggers");
        let new_restart = trigger_value(new_source, "X-Restart-Triggers");
        let old_reload = trigger_value(old_source, "X-Reload-Triggers");
        let new_reload = trigger_value(new_source, "X-Reload-Triggers");

        if !new_restart.is_empty() && old_restart != new_restart {
            actions.push(TriggerAction {
                action: "restart".to_string(),
                unit: unit.clone(),
                reason: "restart trigger changed".to_string(),
            });
            continue;
        }

        if !new_reload.is_empty() && old_reload != new_reload {
            actions.push(TriggerAction {
                action: "reload".to_string(),
                unit: unit.clone(),
                reason: "reload trigger changed".to_string(),
            });
        }
    }

    actions
}

fn unit_sources(manifest: &Manifest) -> HashMap<String, PathBuf> {
    let mut sources = HashMap::new();

    for file in &manifest.files {
        if file.kind != FileKind::Symlink {
            continue;
        }
        let Some(source) = &file.source else {
            continue;
        };
        let target = file.target.to_string_lossy();
        if !target.contains("/systemd/user/") {
            continue;
        }
        let Some(name) = file.target.file_name() else {
            continue;
        };
        let unit = name.to_string_lossy();
        if !(unit.ends_with(".service") || unit.ends_with(".timer") || unit.ends_with(".socket")) {
            continue;
        }

        sources.insert(unit.to_string(), source.clone());
    }

    sources
}

fn trigger_value(path: &Path, key: &str) -> String {
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(_) => return String::new(),
    };

    let prefix = format!("{key}=");
    let reader = BufReader::new(file);
    for line in reader.lines() {
        let Ok(line) = line else {
            continue;
        };
        if let Some(value) = line.strip_prefix(&prefix) {
            return value.to_string();
        }
    }

    String::new()
}

fn atomic_copy(src: &Path, dst: &Path) -> Result<(), String> {
    let parent = dst
        .parent()
        .ok_or_else(|| format!("state path has no parent: {}", dst.display()))?;
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;

    let tmp = parent.join(format!(".hjem-manifest-{}.tmp", std::process::id()));
    fs::copy(src, &tmp)
        .map_err(|e| format!("failed to copy '{}' to '{}': {e}", src.display(), tmp.display()))?;
    fs::rename(&tmp, dst).map_err(|e| {
        format!(
            "failed to replace state manifest '{}' with '{}': {e}",
            dst.display(),
            src.display()
        )
    })?;

    Ok(())
}

fn print_json<T: Serialize>(value: &T) -> Result<(), String> {
    let output = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    println!("{output}");
    Ok(())
}

fn standalone_state_dir(override_dir: Option<PathBuf>) -> Result<PathBuf, String> {
    if let Some(path) = override_dir {
        return Ok(path);
    }

    if let Ok(xdg) = std::env::var("XDG_STATE_HOME") {
        return Ok(PathBuf::from(xdg).join("hjem").join("standalone"));
    }

    let home = std::env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    Ok(PathBuf::from(home)
        .join(".local")
        .join("state")
        .join("hjem")
        .join("standalone"))
}

fn record_generation(base: &Path, manifest: &Path) -> Result<String, String> {
    let generation_id = now_id("generation");
    let generation_dir = base.join("generations").join(&generation_id);
    fs::create_dir_all(&generation_dir).map_err(|e| e.to_string())?;
    atomic_copy(manifest, &generation_dir.join("manifest.json"))?;
    Ok(generation_id)
}

fn list_generations(base: &Path) -> Result<Vec<PathBuf>, String> {
    let generations_dir = base.join("generations");
    if !generations_dir.exists() {
        return Ok(Vec::new());
    }

    let mut out = Vec::new();
    for entry in fs::read_dir(&generations_dir).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        if entry.path().is_dir() {
            out.push(entry.path());
        }
    }
    out.sort();
    Ok(out)
}

fn resolve_generation_manifest(base: &Path, generation: Option<&str>) -> Result<PathBuf, String> {
    let generations = list_generations(base)?;
    if generations.is_empty() {
        return Err("No generations available".to_string());
    }

    let chosen = if let Some(generation) = generation {
        base.join("generations").join(generation)
    } else {
        generations
            .last()
            .cloned()
            .ok_or_else(|| "No generations available".to_string())?
    };

    let manifest = chosen.join("manifest.json");
    if !manifest.exists() {
        return Err(format!(
            "Generation manifest missing: {}",
            manifest.display()
        ));
    }
    Ok(manifest)
}

fn generation_id_from_path(path: &Path) -> Option<String> {
    path.file_name().map(|x| x.to_string_lossy().to_string())
}

fn generation_timestamp_from_id(id: &str) -> Option<u64> {
    let (_, ts) = id.rsplit_once('-')?;
    ts.parse::<u64>().ok()
}

fn parse_expire_timestamp(input: &str) -> Result<u64, String> {
    let trimmed = input.trim();

    if let Ok(unix) = trimmed.parse::<u64>() {
        return Ok(unix);
    }

    if let Some(days_str) = trimmed
        .strip_prefix('-')
        .and_then(|s| s.strip_suffix(" days"))
        .or_else(|| trimmed.strip_suffix("d"))
    {
        let days = days_str
            .trim()
            .parse::<u64>()
            .map_err(|_| format!("Invalid relative day count: {input}"))?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| e.to_string())?
            .as_secs();
        return Ok(now.saturating_sub(days.saturating_mul(24 * 60 * 60)));
    }

    if let Ok(dt) = DateTime::parse_from_rfc3339(trimmed) {
        let ts = dt.timestamp();
        return u64::try_from(ts).map_err(|_| format!("Timestamp is before epoch: {input}"));
    }

    if let Ok(date) = NaiveDate::parse_from_str(trimmed, "%Y-%m-%d") {
        let Some(dt) = date.and_hms_opt(0, 0, 0) else {
            return Err(format!("Invalid date: {input}"));
        };
        let ts = DateTime::<Utc>::from_naive_utc_and_offset(dt, Utc).timestamp();
        return u64::try_from(ts).map_err(|_| format!("Timestamp is before epoch: {input}"));
    }

    Err(format!(
        "Unsupported timestamp format '{input}'. Use unix seconds, YYYY-MM-DD, RFC3339, or -N days"
    ))
}

fn read_current_generation_id(base: &Path) -> Result<Option<String>, String> {
    let file = base.join("current-generation");
    if !file.exists() {
        return Ok(None);
    }
    let content = fs::read_to_string(file).map_err(|e| e.to_string())?;
    let id = content.trim().to_string();
    if id.is_empty() {
        Ok(None)
    } else {
        Ok(Some(id))
    }
}

fn set_current_generation_id(base: &Path, id: &str) -> Result<(), String> {
    fs::create_dir_all(base).map_err(|e| e.to_string())?;
    let current = base.join("current-generation");
    let current_tmp = base.join(format!(".current-generation-{}", std::process::id()));
    fs::write(&current_tmp, format!("{id}\n")).map_err(|e| e.to_string())?;
    fs::rename(&current_tmp, &current).map_err(|e| e.to_string())?;
    Ok(())
}

fn previous_generation_id(base: &Path) -> Result<String, String> {
    let mut ids = list_generations(base)?
        .into_iter()
        .filter_map(|p| generation_id_from_path(&p))
        .collect::<Vec<_>>();
    ids.sort();
    if ids.len() < 2 {
        return Err("No previous generation available for rollback".to_string());
    }

    if let Some(current) = read_current_generation_id(base)? {
        if let Some(idx) = ids.iter().position(|id| id == &current) {
            if idx == 0 {
                return Err("No previous generation available for rollback".to_string());
            }
            return Ok(ids[idx - 1].clone());
        }
    }

    Ok(ids[ids.len() - 2].clone())
}

fn write_last_source(base: &Path, source: &StandaloneSource) -> Result<(), String> {
    fs::create_dir_all(base).map_err(|e| e.to_string())?;
    let path = base.join("last-source");
    let content = match source {
        StandaloneSource::Manifest(path) => format!("manifest={}\n", path.display()),
        StandaloneSource::Config(path) => format!("config={}\n", path.display()),
        StandaloneSource::Flake(path) => format!("flake={}\n", path.display()),
        StandaloneSource::FlakeWithAttr(flake, attr) => {
            let attr = attr.clone().unwrap_or_default();
            format!("flake={flake}\nflakeAttr={attr}\n")
        }
    };
    fs::write(path, content).map_err(|e| e.to_string())
}

fn standalone_config_dir(dir: Option<PathBuf>) -> Result<PathBuf, String> {
    if let Some(dir) = dir {
        return Ok(dir);
    }
    if let Ok(config_home) = std::env::var("XDG_CONFIG_HOME") {
        return Ok(PathBuf::from(config_home).join("hjem"));
    }
    Ok(home_dir()?.join(".config").join("hjem"))
}

fn home_dir() -> Result<PathBuf, String> {
    std::env::var("HOME")
        .map(PathBuf::from)
        .map_err(|_| "HOME is not set".to_string())
}

fn now_id(prefix: &str) -> String {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{prefix}-{ts}")
}
