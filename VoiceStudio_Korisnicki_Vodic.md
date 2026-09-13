# VoiceStudio — Korisnički priručnik i upute

> **Lokalna alternativa za ElevenLabs** — kloniranje glasa, dizajn likova, audio knjige, prevođenje i optimizacija na vlastitom računalu bez oblaka i pretplata.

---

## 1. O aplikaciji VoiceStudio

VoiceStudio omogućuje profesionalno generiranje i kloniranje govora na vašem lokalnom hardveru. Svi modeli i podaci obrađuju se na vašem računalu (**NVIDIA GeForce RTX 4060 s CUDA ubrzanjem**), što jamči potpunu privatnost, neograničeno korištenje i nultu latenciju prema vanjskim poslužiteljima.

---

## 2. Kloniranje glasa (Voice Cloning)

Kloniranje glasa omogućuje precizno kopiranje boje, tona i intonacije iz kratkog uzorka snimke.

### Koraci za kvalitetno kloniranje:
1. **Odabir uzorka (Reference audio):**
   * Isječak treba trajati između **5 i 15 sekundi**.
   * Zvuk mora biti čist, bez pozadinske glazbe, jeke i šumova (WAV, MP3 ili M4A format).
2. **Učitavanje u VoiceStudio:**
   * Povucite audio datoteku u polje *Reference audio*.
3. **Unos željenog teksta:**
   * U gornji prozor upišite tekst koji želite da klonirani glas izgovori.
4. **Ključni korak za maksimalnu brzinu (Transcript):**
   * Ispod učitane snimke kliknite na strelicu **`Optional details`**.
   * U polje **`Transcript`** upišite točne riječi koje govornik izgovara u toj referentnoj snimci.
   * *Zašto je ovo važno?* Ako ovo polje ostane prazno, VoiceStudio mora najprije pokrenuti Whisper AI model da sam prepozna riječi, što usporava početak generiranja.
5. **Generiranje:**
   * Pritisnite ružičasti gumb **`Synthesize`**. Za rečenicu od 10 sekundi potrebno je tek oko **2 do 3 sekunde** obrade.

---

## 3. Podešavanje brzine i parametara zvuka (Production Overrides)

Iznad gumba *Synthesize* kliknite na **`Production Overrides ^`** za pristup naprednim kontrolama:

| Parametar | Što radi | Preporučena vrijednost |
|---|---|---|
| **Speed (Brzina)** | Kontrolira brzinu izgovora (0.5× do 2.0×) | `0.85× – 0.95×` ako je govor prebrz; `1.0×` zadano |
| **CFG (Guidance Scale)** | Koliko se model strogo drži referentnog glasa | `2.0` (zadano) |
| **Steps (Koraci difuzije)** | Broj iteracija obrade zvuka (kvaliteta vs. brzina) | `16 – 32` |
| **Duration (Trajanje)** | Fiksno trajanje u sekundama ako usklađujete s videom | `Auto` (ili točan broj sekundi) |
| **Denoise** | Automatsko uklanjanje pozadinskog šuma | Uključeno (`On`) |

---

## 4. Ritam govora, pauze i emocije (Interpunkcija)

Modeli govora izravno reagiraju na znakove interpunkcije u tekstu:
* **Zarez (`,`)**: stvara kratku, prirodnu stanku za udah.
* **Trotočje (`...`)**: stvara dužu, promišljenu pauzu.
* **Crtica (`—`)**: stvara nagli prekid ili promjenu ritma.
* **Upitnik (`?`) i Uskličnik (`!`)**: prirodno moduliraju visinu tona na kraju rečenice.

---

## 5. Ostale funkcionalnosti

* **Voice Design (Dizajn glasa):** Generiranje novih glasova putem tekstualnog opisa (npr. *"stariji muškarac dubokog i smirenog glasa"*).
* **Video Dubbing (Sinkronizacija):** Automatsko prevođenje i presnimavanje videa s odvajanjem vokala od pozadinske glazbe.
* **Audiobook & Stories:** Višeglasni uređivač za priče i knjige (dodjela različitih glasova različitim likovima) s izvozom u MP3/M4B.
* **Dictation (Diktiranje):** Brzo pretvaranje govora u tekst izravno u bilo koji Windows program.

---

## 6. Savjeti za rad i rješavanje problema

* **Čista grafička memorija:** Ako koristite programe poput *LM Studio*, ugasite ih dok radite u VoiceStudiju kako bi svih 8 GB VRAM-a bilo slobodno.
* **Brzo pokretanje:** Na radnoj površini kreiran je prečac **`Pokreni VoiceStudio`** koji automatski provjerava portove, pokreće servise i otvara aplikaciju u pregledniku.
