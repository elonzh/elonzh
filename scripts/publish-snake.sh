#!/usr/bin/env bash
set -euo pipefail

image_file="$(cd "$(dirname "${1:?Usage: publish-snake.sh <image.gif>}")" && pwd)/$(basename "$1")"
image_name="$(basename "$image_file")"
test -s "$image_file"
case "$(head -c 6 "$image_file")" in
  GIF87a|GIF89a) ;;
  *) echo "Expected a generated GIF: $image_name" >&2; exit 1 ;;
esac

: "${SNAKE_REPOSITORY_URL:?Set the destination repository URL.}"
: "${SNAKE_TOKEN:?Set the CI repository token.}"
: "${SNAKE_COMMITTER_NAME:?Set the commit author name.}"
: "${SNAKE_COMMITTER_EMAIL:?Set the commit author email.}"

# Publish from a separate repository so the source checkout remains untouched.
publish_dir="$(mktemp -d)"
trap 'rm -rf "$publish_dir"' EXIT
cat > "$publish_dir/askpass" <<'ASKPASS'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "${SNAKE_TOKEN_USER:-x-access-token}" ;;
  *Password*) printf '%s\n' "$SNAKE_TOKEN" ;;
esac
ASKPASS
chmod 700 "$publish_dir/askpass"
export GIT_ASKPASS="$publish_dir/askpass"
export GIT_TERMINAL_PROMPT=0

git init --quiet --initial-branch=output "$publish_dir/repo"
cd "$publish_dir/repo"
git remote add origin "$SNAKE_REPOSITORY_URL"
output_ref="$(git ls-remote --heads origin refs/heads/output)"
if [ -n "$output_ref" ]; then
  git fetch --quiet --depth=1 origin refs/heads/output
  git checkout --quiet -B output FETCH_HEAD
fi
cp "$image_file" "$image_name"
git add -- "$image_name"
if git diff --cached --quiet; then
  echo "$image_name is unchanged."
  exit 0
fi
git -c user.name="$SNAKE_COMMITTER_NAME" \
    -c user.email="$SNAKE_COMMITTER_EMAIL" \
    commit --quiet \
    -m 'chore(profile): 更新贡献动画 [skip ci]' \
    -m "发布重新生成的 ${image_name}，仅更新 output 分支的对应图片。" \
    -m '验证：生成文件非空，GIF 文件签名有效。'
git push --quiet origin HEAD:refs/heads/output
