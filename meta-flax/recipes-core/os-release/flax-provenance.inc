# Build-provenance block appended to /etc/os-release.
#
# Owned by meta-flax so it survives the move onto a canonical OpenBMC tree --
# the AMI/Intel layers that used to do this are BBMASKed in conf/layer.conf.
# Their repo_status() had four defects: the block was emitted twice (both
# meta-ami and meta-common/meta-common shipped a do_compile:append), every
# untracked file was dumped with an eight-level ../../ prefix (git ran with
# cwd=${B}), a nonexistent repo rendered as "OneTree-0.0-0-gfatal:" (the
# "fatal:" error string was interpolated as if it were a hash), and the tag was
# fabricated whenever git describe found no match.
#
# Policy: quiet when the tree is clean, detailed only when it is dirty.
# Dirtiness is tracked-file modifications only, matching `git describe --dirty`
# -- untracked scratch files do not affect the build and are never named.
#
#   # Build Provenance
#   # openbmc-ami: 3a95f53
#   # meta-ami:    ad131770-dirty
#   #   M meta-common/recipes-ami/spdm/spdmapplib_lfmctp.inc
#   #   (3 untracked files not listed)

def flax_is_git_repo(repo):
    import os
    # A layer with no .git of its own (meta-megarac) would otherwise report the
    # *parent* repo's HEAD -- worse than saying nothing at all.
    return os.path.exists(os.path.join(repo, '.git'))

def flax_provenance_lines(run, repos):
    """Render the provenance block.  `run(repo, args)` returns git's stdout, or
    None if the command failed; keeping it injected makes this testable off-box."""
    import os

    present = [r for r in repos if flax_is_git_repo(r)]
    if not present:
        return []

    names = [os.path.basename(r.rstrip('/')) or r for r in present]
    width = max(len(n) for n in names) + 1

    lines = ['', '# Build Provenance']
    for repo, name in zip(present, names):
        desc = run(repo, ['describe', '--tags', '--always', '--dirty'])
        if desc is None:
            # Present but unreadable: say so rather than inventing a version.
            desc = '(unavailable)'
        lines.append('# {} {}'.format((name + ':').ljust(width), desc))

        tracked = run(repo, ['status', '--porcelain', '--untracked-files=no']) or ''
        if not tracked.strip():
            continue
        for entry in tracked.splitlines():
            lines.append('#   ' + entry.strip())
        allfiles = run(repo, ['status', '--porcelain', '--untracked-files=all']) or ''
        n = len([e for e in allfiles.splitlines() if e.startswith('??')])
        if n:
            lines.append('#   ({} untracked file{} not listed)'.format(
                n, '' if n == 1 else 's'))
    return lines

def flax_git(d, repo, args):
    """BitBake-side runner.  cwd=repo is what keeps `git status` paths relative
    to the repo instead of eight levels up from ${B}."""
    import bb.process
    try:
        out, _err = bb.process.run(['git'] + args, cwd=repo)
        return out.strip('\n')
    except Exception:
        return None
