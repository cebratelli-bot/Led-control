# LED Control

App Android (Flutter) para controlar fitas de LED Magic Home pelo Wi-Fi, sem nuvem.

## O que faz
- Busca as fitas automaticamente na rede (ou adiciona pelo IP)
- Liga e desliga cada fita, ou todas de uma vez
- Cor, saturação e brilho, com cores rápidas
- 20 efeitos (arco-íris, respirar, piscar…) com controle de velocidade
- Controla todas as fitas juntas na mesma cor
- Segure o dedo numa fita para renomear ou remover

## Como gerar o APK

### Opção 1: no seu PC
1. Instale o Flutter: https://docs.flutter.dev/get-started/install (com o Android Studio)
2. Dentro desta pasta, rode:
   ```
   flutter create --platforms=android --project-name led_control .
   flutter pub get
   flutter test
   flutter build apk --release
   ```
   O `flutter create` só cria os arquivos que faltam. Ele não apaga o código do app.
3. O APK fica em `build/app/outputs/flutter-apk/app-release.apk`. Passe para o celular e instale.

Para testar direto no celular com cabo USB (depuração USB ativada): `flutter run`.

### Opção 2: sem instalar nada (GitHub)
1. Crie um repositório no GitHub e envie esta pasta.
2. A aba **Actions** roda o build sozinha (arquivo `.github/workflows/build-apk.yml`).
3. Quando terminar, baixe o APK em "Artifacts" → `led-control-apk`.

## Se não achar as fitas
- O celular precisa estar no **mesmo Wi-Fi** das fitas (redes 2.4 GHz e 5 GHz do mesmo roteador geralmente funcionam)
- Feche o app Magic Home, porque algumas fitas aceitam poucas conexões ao mesmo tempo
- Redes com "isolamento de clientes" (Wi-Fi de visitante) bloqueiam a busca
- Se a busca falhar, veja o IP da fita no app do roteador e use **+ Adicionar pelo IP**

## Estrutura
- `lib/magic_home.dart` — protocolo (descoberta UDP 48899, comandos TCP 5577)
- `lib/main.dart` — telas
- `test/widget_test.dart` — confere os bytes dos comandos
