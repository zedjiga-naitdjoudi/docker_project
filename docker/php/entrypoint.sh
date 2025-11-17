#!/bin/bash
set -e

cd /var/www/html || exit 1
echo "entrypoint démarré" #log #a suuprimer apres 

##############################################################################
#créer .env si absent uniquement sur le premier conteneur
##############################################################################
if [ ! -f .env ]; then
    echo "création du fichier .env" #jfais des echos pour mes logs apres 

    cp .env.example .env

    # injecter les variables db uniquement a la création
    sed -i "s/^DB_HOST=.*/DB_HOST=${DB_HOST}/" .env
    sed -i "s/^DB_PORT=.*/DB_PORT=${DB_PORT}/" .env
    sed -i "s/^DB_DATABASE=.*/DB_DATABASE=${DB_DATABASE}/" .env
    sed -i "s/^DB_USERNAME=.*/DB_USERNAME=${DB_USERNAME}/" .env
    sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASSWORD}/" .env
else
    echo ".env déjà existant aucune modification appliquée"
fi

##############################################################################
#attendre que mysql soit prêt
##############################################################################
echo "attente mysql..."
until php -r "try { new PDO('mysql:host=${DB_HOST};port=${DB_PORT}', '${DB_USERNAME}', '${DB_PASSWORD}'); } catch (Exception \$e) { exit(1);}"; do
  sleep 2
done
echo "mysql prêt"

##############################################################################
#installer composer si le dossier vendor est absent
##############################################################################
if [ ! -d vendor ]; then
    echo "installation des dépendances composer"
    composer install --no-interaction --prefer-dist --optimize-autoloader
fi


##############################################################################
# générer app_key si absente ou vide
##############################################################################
if ! grep -q '^APP_KEY=' .env || [ -z "$(grep '^APP_KEY=' .env | cut -d '=' -f2)" ]; then
    echo "APP_KEY manquant ou vide, génération..."
    php artisan key:generate --force
else
    echo "APP_KEY déjà définie, rien à faire"
fi





##############################################################################
#lancer les migrations si RUN_MIGRATIONS=true 
#technique de bz : utiliser un lock !!!!!!!!
#empêcher que plusieurs processus fassent la même action en même temps
#pour pas que les conteneurs exécutent php artisan migrate en mm temps
##############################################################################
if [ "${RUN_MIGRATIONS}" = "true" ]; then

    echo "migrations activées sur ce conteneur"

    TABLE_EXISTS=$(php -r "
        try {
            \$pdo = new PDO('mysql:host=${DB_HOST};dbname=${DB_DATABASE};port=${DB_PORT}', '${DB_USERNAME}', '${DB_PASSWORD}');
            \$stmt = \$pdo->query(\"SHOW TABLES LIKE 'migrations'\");

            echo \$stmt && \$stmt->fetch() ? '1' : '';
        } catch (Exception \$e) {
            echo '';
        }
    ")

    if [ -z "$TABLE_EXISTS" ]; then
        echo "base vide lancement de migrate avec seed"
        php artisan migrate --seed --force
    else
        echo "table migrations existe déjà migrations ignorées"
    fi
else
    echo "migrations ignorées pour ce conteneur"
fi

##############################################################################
#lancer php-fpm
##############################################################################
echo "lancement de php-fpm"
exec php-fpm
