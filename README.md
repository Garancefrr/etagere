# 📚 Étagère — Bibliothèque personnelle

PWA Next.js 14 pour gérer votre bibliothèque de livres, BDs et mangas.
Scan ISBN · Collections automatiques · Partage famille · Mode clair/sombre

## Stack
- **Next.js 14** App Router + TypeScript
- **Supabase** PostgreSQL + Auth Google
- **ZXing** scanner codes-barres (caméra)
- **Open Library + Google Books** lookup ISBN + détection de série
- **DM Sans** (Google Fonts) · Tailwind CSS · CSS variables pour le thème

## Fonctionnalités principales
- Scan ISBN → infos automatiques (titre, auteur, couverture, éditeur)
- **Création automatique de collection** quand on scanne une BD/manga avec `series_name` dans les métadonnées
- Mise à jour automatique des tomes manquants lors d'un scan
- Bibliothèque partagée (famille/amis) avec rôles
- Mode clair / sombre persisté (localStorage + CSS variables)
- PWA installable iOS/Android

## Installation

```bash
npm install
cp .env.example .env.local   # remplir les valeurs
npm run dev                  # → http://localhost:3000
```

## Variables d'environnement
Voir `.env.example` — Supabase + Google OAuth + NextAuth secret.

## Déploiement Vercel
```bash
vercel deploy
```
Ajouter les variables dans le dashboard Vercel.

## Schéma Supabase
Exécuter `supabase-schema.sql` dans l'éditeur SQL Supabase.

## Logique collection auto (src/lib/collection-service.ts)
1. ISBN scanné → Open Library / Google Books
2. Si `series_name` + `series_index` détectés ET `book_type` = bd/manga :
   - Collection existante → tome ajouté, manquants recalculés
   - Nouvelle série → collection créée automatiquement
3. Sinon → ajout simple dans la bibliothèque

## Pages
- `/library` — grille 4 colonnes, filtres, hero band stats
- `/collections` — séries avec barres de progression et chips de tomes
- `/scan` — scanner ISBN + confirmation intelligente
- `/stats` — KPIs, répartition, top auteurs
- `/settings` — profil, membres, toggle dark mode, export
