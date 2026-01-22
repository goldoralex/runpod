#!/bin/bash

echo "🛠️  Vérification des dossiers de persistance..."

# Création des dossiers dans /workspace s'ils n'existent pas
# Le -p permet de ne pas faire d'erreur si le dossier existe déjà
mkdir -p "$OLLAMA_MODELS"
mkdir -p "$DATA_DIR"

echo "📂 Dossiers configurés :"
echo "   - Ollama : $OLLAMA_MODELS"
echo "   - WebUI  : $DATA_DIR"

# 1. Démarrer Ollama en arrière-plan
echo "🚀 Démarrage du serveur Ollama..."
ollama serve &

# Attente active : on attend que le serveur réponde avant de continuer
# C'est plus robuste que "sleep 5"
echo "⏳ Attente du démarrage de l'API Ollama..."
until curl -s http://localhost:11434/api/tags > /dev/null; do
    sleep 1
done
echo "✅ Ollama est prêt !"

# 2. (Optionnel) Charger les modèles automatiquement
# On vérifie d'abord si le modèle n'est pas DÉJÀ dans le dossier persistant
if [ ! -z "$MODEL_TO_LOAD" ]; then
    # Petite astuce : on liste les modèles pour voir si on l'a déjà
    if ollama list | grep -q "$MODEL_TO_LOAD"; then
        echo "💾 Le modèle $MODEL_TO_LOAD est déjà présent sur le disque."
    else
        echo "📥 Le modèle $MODEL_TO_LOAD n'est pas trouvé, téléchargement en cours..."
        ollama pull $MODEL_TO_LOAD
    fi
fi

# 3. Démarrer Open-WebUI
echo "🌐 Démarrage de Open-WebUI..."
# Open-WebUI va lire la variable DATA_DIR automatiquement
open-webui serve