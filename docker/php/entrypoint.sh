#!/bin/bash
set -e

echo "🟢 Entrypoint démarré pour $(hostname)"

# Attendre que les variables DB existent
: "${DB_HOST:=mysql}"
: "${DB_PORT:=3306}"
: "${DB_DATABASE:=laravel}"
: "${DB_USERNAME:=laravel}"
: "${DB_PASSWORD:=laravelpw}"

# Fonction d'attente PDO
wait_for_mysql() {
  echo "⏳ Attente de MySQL (${DB_HOST}:${DB_PORT})..."
  until php -r "try { new PDO('mysql:host=${DB_HOST};port=${DB_PORT};dbname=${DB_DATABASE}', '${DB_USERNAME}', '${DB_PASSWORD}'); echo 'ok'; } catch (Exception \$e) { exit(1); }" >/dev/null 2>&1; do
    sleep 2
    echo "⏳ Encore..."
  done
  echo "✔ MySQL prêt"
}

# Si .env absent, essayer de copier .env.example et remplacer les valeurs DB par celles du conteneur
prepare_env() {
  if [ ! -f .env ]; then
    if [ -f .env.example ]; then
      echo "Création de .env depuis .env.example"
      cp .env.example .env
      # remplacer les valeurs DB dans .env (si présentes)
      sed -i "s/^DB_HOST=.*/DB_HOST=${DB_HOST}/" .env || true
      sed -i "s/^DB_PORT=.*/DB_PORT=${DB_PORT}/" .env || true
      sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/" .env || true
      sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/" .env || true
      sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" .env || true
      # set APP_URL if not set or points to localhost
      if ! grep -q "^APP_URL=" .env; then
        echo "APP_URL=http://localhost" >> .env
      fi
    else
      echo "Aucune .env ni .env.example trouvée — continue quand même"
    fi
  else
    echo ".env trouvé — on ne l’écrase pas"
  fi
}

# main
cd /var/www/html || exit 1

# s'assurer que l'uid/gid de www-data possède les fichiers (utile en dev)
chown -R www-data:www-data /var/www/html || true

prepare_env
wait_for_mysql

# Installer composer si besoin
if [ ! -d "vendor" ]; then
  echo "📦 Installation Composer..."
  composer install --no-interaction --prefer-dist --optimize-autoloader
else
  echo "vendor déjà présent, skipping composer install"
fi

# Installer dependencies JS et build si public/build absent (ou si package.json changé)
if [ ! -d "node_modules" ] || [ ! -d "public/build" ]; then
  if [ -f package.json ]; then
    echo "📦 Installation NPM et build..."
    npm install
    npm run build || echo "npm run build a échoué mais on continue"
  else
    echo "Aucun package.json — skip npm"
  fi
else
  echo "node_modules et public/build présents, skip npm"
fi

# clé app et migrations : n'exécuter que si la clé est vide ou si les tables manquent
if ! php artisan key:generate --show >/dev/null 2>&1; then
  echo "🔐 key:generate"
  php artisan key:generate
fi

# Exécuter migrate:fresh --seed uniquement si la table users est absente (premier lancement)
if ! php -r "try { \$pdo=new PDO('mysql:host=${DB_HOST};dbname=${DB_DATABASE}', '${DB_USERNAME}', '${DB_PASSWORD}'); \$res=\$pdo->query(\"SHOW TABLES LIKE 'users'\"); if(!\$res || \$res->rowCount()===0) exit(1); } catch (Exception \$e){ exit(1);}"; then
  echo "🛠️ Exécution des migrations et seed (premier démarrage)"
  php artisan migrate:fresh --seed --force
else
  echo "Migrations déjà appliquées, skip migrate:fresh"
fi

# Lancer php-fpm (remplacer le process courant)
echo "▶ Lancement de php-fpm"
exec php-fpm
