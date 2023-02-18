self: project:
if builtins.pathExists "${toString self}/${project.relPath}/Cargo.lock"
then {
  inherit project;
  hasLock = true;
}
else
  builtins.trace
  ''
    Cargo.lock not found for project at path ${project.relPath}.
    Please ensure the lockfile exists for your project.
    If you are using a VCS, ensure the lockfile is added to the VCS and not ignored (eg. run `git add path/to/project/Cargo.lock` for git).

    This project will be skipped and won't have any outputs generated.
    Run `nix run .#generate-lockfiles` to generate lockfiles for projects that don't have one.
  ''
  {
    inherit project;
    hasLock = false;
  }
