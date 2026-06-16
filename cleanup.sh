#!/bin/bash
set -e
echo "🧹 Nettoyage final..."
cd "$(git rev-parse --show-toplevel)"

# 1. Supprimer fichiers/dossiers obsolètes
rm -rf src/app/wishlist
rm -rf src/app/api/wishlist
rm -rf src/app/api/share/token
rm -f  src/lib/data.ts

echo "✅ Fichiers obsolètes supprimés"

git add -A
git status --short
git commit -m "chore: remove dead files (wishlist, data.ts, share/token)"
git push
echo "🎉 Nettoyé et déployé !"
