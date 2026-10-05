# NEXA AI phone app (Android, Flutter)

A complete native app. Nothing in it is a web page.

| Screen | What you can do |
|---|---|
| Home | See NEXA and every employee live, talk by typing or by voice (English and Urdu), allow or deny risky actions (with PIN), watch the laptop screen, stop everyone, switch Office / Café |
| Tasks | History of finished tasks with their steps and "Run again"; the queue of each robot; timed tasks (add, switch off, delete) |
| Fun | Café conversations |
| Team | Every robot's state; change speciality, block risky actions, retire, hire |
| More | Language, Hey NEXA on or off, mute, run skills, memory, learned tasks, AI services, scan another code, unpair |

It reaches the laptop two ways and chooses by itself: home Wi-Fi when it can (fastest), otherwise the
away link through your website (see `relay\README.txt`).

**Honest status:** this app has never been compiled. Claude has no Flutter tools in its workspace; the code
was checked for syntax only. The first build may stop with an error. If it does, copy the red lines from
the GitHub Actions page and send them to Claude.

## What is in this folder

| File | What it is |
|---|---|
| `lib\main.dart` | Start of the app and the pairing (scanner) screen |
| `lib\remote.dart` | The five screens |
| `lib\link.dart` | Talking to the laptop: signed requests on Wi-Fi, AES-256 locked messages through the relay |
| `lib\ui.dart` | Colours and small building blocks |
| `icons\` | The app icon in every Android size |
| `patch_android.py` | Sets the app name, permissions and icon during the build |
| `build-workflow.txt` | The GitHub build recipe |

The Android project files (Gradle and so on) are created fresh by GitHub during each build, so they always
match the newest Flutter. You do not need them here.

## Build it on GitHub

1. On github.com click **New repository**. Name: `nexa-app`. Private. Create.
   (If you made this repository before: open it, delete the old `main.dart`, then continue.)
2. Click **uploading an existing file**. From `Downloads\NEXA AI\phone-app` drag in the **`lib` folder**,
   the **`icons` folder** and `patch_android.py`. Click **Commit changes**.
3. Click **Add file > Create new file**. In the name box type exactly:
   `.github/workflows/build.yml`
   Open `phone-app\build-workflow.txt` in Notepad, copy everything, paste it in. **Commit changes**.
   (If the file already exists: open it, click the pencil, replace everything, commit.)
4. Open the **Actions** tab. "Build NEXA AI app" starts by itself (about 8 minutes).
5. Green tick: open the run, scroll to **Artifacts**, download **nexa-ai-app**. The zip holds `app-release.apk`.
   Red cross: open the run, open the red step, copy the red lines, send them to Claude.
6. Send the APK to the phone, tap it, allow "install unknown apps", install.

## Use it

1. Laptop: NEXA AI > Settings > **Phone link** > On. Phone: open NEXA AI, allow the camera, scan the code
   "At home (same Wi-Fi)". Windows asks once to allow Python on private networks: Allow.
2. For anywhere: do the three steps in `relay\README.txt`, turn on Settings > **Away link**, then in the app
   open **More > Scan another code** and scan "Anywhere (your website)".
3. The first time you press the microphone, allow it. Speak; when you stop, the words go to NEXA.
   Urdu needs Urdu offline speech in the phone's Google settings on some phones.

## Not in the app yet

- Notifications while the app is closed (an approval only buzzes the phone while the app is open).
- iPhone. The code is Flutter, so it can be built for iPhone later on a Mac.
