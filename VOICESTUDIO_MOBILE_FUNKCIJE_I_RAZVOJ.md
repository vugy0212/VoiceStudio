# VoiceStudio Mobile — Dokumentacija implementiranih funkcija i arhitektura za daljnji razvoj

> **Verzija:** 1.2.0 (Mobile Architecture & Multi-User Release)  
> **Ažurirano:** 28. listopada 2026.  
> **Ciljne platforme:** Android (testirano na Samsung Galaxy S25 Ultra, Android 17 / API 37) i iOS  
> **Pozadinski poslužitelj:** NVIDIA GeForce RTX 4060 (8GB VRAM) s CUDA akceleracijom, On-Demand Gateway i Cloudflare Zero Trust Tunnel  

---

## 1. Pregled arhitekture sustava

VoiceStudio sustav sastoji se od tri međusobno povezane komponente:

```
[ Mobilni klijent (Flutter) ]
       │  ▲
       │  │ (Lokalni Wi-Fi / USB reverse tcp:3900 ILI Cloudflare Tunel https://studiovoice.trustshome.org)
       ▼  │
[ On-Demand Tihi Gateway (Node/Bun: 3900) ] ◄──► [ Firebase Hub (voicestudio-mobile-hub) ]
       │  ▲
       │  │ (Interni poziv: 3905)
       ▼  │
[ Python OmniVoice Backend (CUDA RTX 4060) ]
```

### 1.1 Mobilna aplikacija (`mobile_app/voicestudio_mobile`)
* **Tehnologija:** Flutter 3.x / Dart 3.x, Provider state management, JustAudio, Dio HTTP klijent.
* **Dizajn:** Dark Neon Studio estetika (duboke tamne pozadine `#0A0D14`, tirkizni `#00E5FF` i neon zeleni akcenti `#00FF9D`).
* **Responzivnost:** Potpuna prilagodba modernim visokim ekranima (uključujući `1080×2340` na S25 Ultra), eliminirani svi `Row` overflowovi i implementirana `SafeArea` zaštita od Android navigacijske trake sa 3 gumba.

### 1.2 On-Demand Tihi Gateway (`scripts/on-demand-gateway.mjs`)
* **Sluša na portu:** `3900` (izložen prema kućnoj mreži i Cloudflare tunelu).
* **Interni backend:** `3905`.
* **Glavne odgovornosti:**
  * **On-Demand aktivacija:** Ako nema zahtjeva 15 minuta, backend prelazi u stanje spavanja (`SLEEPING`) radi štednje struje i oslobađanja 0% GPU resursa. Na prvi korisnički zahtjev automatski budi Python backend.
  * **GPU Red Čekanja (Queue Lock):** Budući da RTX 4060 ima 8GB VRAM-a, postavljen je red čekanja koji dopušta točno 1 aktivnu sintezu na GPU-u, dok se ostali zahtjevi sigurno redaju bez rušenja memorije (OOM).
  * **Filtriranje glasova po ulozi korisnika:** Kroz zaglavlja `x-user-role`, `x-user-id` i `x-custom-voices` kontrolira vidljivost modela za obične i premium korisnike.

### 1.3 Firebase Hub (`voicestudio-mobile-hub`)
* **Firestore kolekcije:**
  * `config/connection`: Dinamička sinkronizacija Cloudflare URL-a, Client ID-a i Secret-a (korisnici ne moraju ručno unositi tokene; admin ih ažurira u Settings, a klijenti automatski preuzimaju).
  * `users/{userId}`: Profili korisnika, uloge (`admin`, `premium`, `user`), dodijeljene grupe glasova, custom glasovi i dnevne kvote.
  * `invites/{code}`: Pozivnice s predefiniranim ulogama i kvotama.

---

## 2. Implementirane korisničke uloge i autorizacija (RBAC)

Aplikacija podržava tri razine pristupa korisnika:

| Uloga | Vidljivost glasovnih modela | Dnevna kvota | Admin ovlasti |
| :--- | :--- | :--- | :--- |
| **Demo (`user`)** | Samo 4 početna modela (`Pantić`, `Šojić`, `dijete`, `Bata Stojković`) + arhetipovi | Predefinirano 10 sinteza / dan | Nema |
| **Premium (`premium`)** | Svi glasovni modeli koje administrator kreira i odobri | Neograničeno (ili po odabiru admina) | Nema |
| **Administrator (`admin`)** | Svi postojeći glasovni modeli, mogućnost kloniranja novih | Neograničeno | Pristup Admin Panelu, upravljanje korisnicima, grupama i postavkama infrastrukture |

* **Sustav pozivnica:** Novi korisnik se može registrirati putem pozivnog koda (`Invite Code`) ili ga administrator može ručno odobriti iz Admin Panela.

---

## 3. Glasovni profili i kurirani arhetipovi

Korisničko sučelje jasno razdvaja stvarne klonirane glasove od sintetičkih arhetipova:

### 3.1 Klonirani glasovi (`Klonirani`)
* Prikazuju isključivo glasove nastale kloniranjem stvarnih audio uzoraka (`kind == 'cloned'`), npr.:
  * *Pantić D.*
  * *Šojić*
  * *Dijete*
  * *Bata Stojković*
  * *Pavle Vujisić*
* **Automatsko čišćenje stila:** Prilikom odabira kloniranog glasa, `AppState.selectProfile` automatski briše zaostale stilske upute (`instruct = ''`) kako prethodno odabrani arhetip ne bi iskrivio autentičnu boju glasa klonirane osobe.

### 3.2 Kurirani arhetipovi (`Arhetipovi (6)`)
Uklonjeni su generički engleski arhetipovi koji su loše izgovarali balkanske jezike, a uvedeno je **6 pažljivo podešenih profila**:
1. **Filmski Narator (HR/SR):** Dubok, topao i autoritativan dokumentarni bas.
2. **TV Voditelj (HR/SR):** Jasan, energičan i informativan ton televizijskih vijesti.
3. **Naratorica (HR/SR):** Topao, prirodan ženski pripovjedački glas za audio knjige i priče.
4. **Voditeljica (HR/SR):** Svjež, artikuliran i profesionalan ženski glas za vijesti i podcaste.
5. **Documentarian (EN):** Britanski duboki narativni glas za engleske tekstove.
6. **Storyteller (EN):** Topao i izražajan narator za engleske priče.

---

## 4. Karaoke sinkronizacija teksta i audio player

### 4.1 Praćenje riječi u realnom vremenu (Karaoke Word-Sync)
* Dok audio svira, riječ koja se trenutno izgovara označena je tirkiznom bojom (`#00E5FF`), a već izgovorene riječi blagim tirkiznim podtonom.
* **Skok na riječ dodirom:** Korisnik može dodirnuti bilo koju riječ u tekstu, nakon čega audio player odmah preskače na taj vremenski trenutak (`tap to seek`).
* **Rješenje skakanja ekrana (`_scrollInnerKaraokeOnly`):**
  * Stari pristup (`Scrollable.ensureVisible`) pomicao je cijeli vanjski `ListView` ekrana gore-dolje pri svakoj novoj riječi.
  * Novi pristup koristi interni `ScrollController` i fiksnu visinu kontejnera (156 px). Proračunom lokalnih koordinata preko `RenderBox.localToGlobal` skrola se isključivo unutrašnji tekst, dok vanjski ekran ostaje 100% miran.
  * Konstantan `padding` i fiksna debljina fonta (`FontWeight.w600`) sprječavaju prelamanje redaka (reflow) tijekom izgovora.

### 4.2 Kontrole zaustavljanja i spremanja (`Stop` i `Snimi`)
* **Gumb `Stop`:** Jasno istaknut crvenom bojom na tri strateška mjesta:
  1. U gornjem desnom kutu kartice teksta tijekom reprodukcije.
  2. U glavnoj akcijskoj traci pored gumba *Sintetiziraj*.
  3. U `NeonAudioPlayer` traci pored tipke za pauzu.
* **Gumb `Snimi`:** Zamijenjena ranija nejasna ikona preuzimanja s jasno označenim gumbom **`[↓ Snimi]`** koji se nakon spremanja u lokalnu offline biblioteku pretvara u **`[✓ Snimljeno]`**.

---

## 5. Admin Panel (`AdminPanelScreen`)

Dostupan samo korisnicima s ulogom `Admin`:

1. **Tab `Korisnici`:**
   * Pregled svih registriranih korisnika i njihovih trenutnih kvota.
   * Promjena uloge jednim dodirom (`Demo (4 glasa)` ⇄ `⭐ Premium (Svi glasovi)`).
   * **`Glasovi / Grupa` modal:** Mogućnost dodjele specifične grupe glasova ili ručni odabir točno određenih glasovnih profila pojedinom korisniku.
   * Blokiranje i brisanje korisnika.
2. **Tab `Grupe Glasova`:**
   * Kreiranje prilagođenih tematskih grupa (npr. *"Domaće serije"*, *"Informativni program"*, *"Edukacija"*).
   * Dodavanje i uklanjanje modela iz grupa.
3. **Tab `Uredi Glasove`:**
   * Pregled svih registriranih modela na poslužitelju.
   * Izravno uređivanje naziva glasa, opisa i metapodataka bez potrebe za pristupom bazi podataka.
4. **Generator pozivnica (`Nova Pozivnica`):**
   * Kreiranje jednokratnih ili višekratnih alfanumeričkih kodova za prijavu novih korisnika s unaprijed definiranom ulogom i trajanjem.

---

## 6. Postavke, Upute i O aplikaciji (`SettingsScreen`)

* **Upute za korištenje (Vodič):** Detaljan vodič unutar same aplikacije koji objašnjava kako klonirati glas, kako koristiti interpunkciju za modulaciju tempa i emocija, te kako koristiti Speechify čitač dugih članaka.
* **O aplikaciji (About):** Tehnički podaci o lokalnom izvođenju, RTX 4060 akceleraciji i jamstvu privatnosti bez slanja podataka na treće poslužitelje.
* **Upravljanje mrežnom vezom:**
  * `⚡ Automatski`: Pokušava lokalnu vezu (Wi-Fi / USB), a ako računalo nije u istoj mreži, automatski se prebacuje na Cloudflare tunel.
  * `🏠 Lokalno`: Izravno na lokalni IP ili `127.0.0.1:3900` preko USB `adb reverse` tunela.
  * `☁️ Cloudflare`: Korištenje zaštićenog Cloudflare Zero Trust tunela s tokenima.
* **Sinkronizacija u Firebase:** Administrator može jednim klikom spremiti novu konfiguraciju tunela i tokena u Firebase, što odmah ažurira sve povezane mobilne uređaje bez potrebe za novim buildom aplikacije.

---

## 7. Smjernice i preporuke za daljnji razvoj (Roadmap)

Sljedeći logični koraci za unapređenje sustava:

1. **Višeglasni dijalozi (Dialogue Studio):**
   * Povezivanje postojećeg `MultiVoiceDialogScreen` s novim multi-user API-jem kako bi korisnici mogli generirati razgovore između 2 ili više odobrenih glasova.
2. **Speech-to-Speech (Prijenos glasa u glas):**
   * Omogućavanje korisniku da snimi vlastiti govor kroz mikrofon mobitela, a model ga u realnom vremenu konvertira u boju glasa odabranog profila (npr. *Pantić* ili *Voditeljica*).
3. **Automatsko slanje push notifikacija (FCM):**
   * Integracija Firebase Cloud Messaginga kako bi korisnik dobio obavijest na mobitel kada administrator odobri njegov zahtjev za Premium ulogom ili kada je dugačak audio fajl dovršen u pozadini.
4. **Napredno upravljanje prostorom na poslužitelju:**
   * Periodično automatsko arhiviranje privremenih WAV generiranja starijih od 30 dana uz zadržavanje trajno spremljenih profila u SQLite bazi.

---

*Dokumentacija pripremljena za repozitorij VoiceStudio.*
