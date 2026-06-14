// lib/services/update_service.dart (VERSION 1.0 - VERSION COMPARISON & COUNTDOWN)

class UpdateService {
  /// 1. GUGERERANYA VERSION (Urugero: "1.0.0" vs "1.1.2")
  /// Igaragaza 'true' niba version ya telefone (current) ari ishaje kurusha iy'ubuyobozi (latest).
  static bool isVersionOlder(String current, String latest) {
    try {
      List<int> currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      List<int> latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      // Ringaniza uburebure bw'urutonde (Urugero niba ari "1.1" vs "1.1.1")
      int maxLength = currentParts.length > latestParts.length ? currentParts.length : latestParts.length;
      
      for (int i = 0; i < maxLength; i++) {
        int currentVal = i < currentParts.length ? currentParts[i] : 0;
        int latestVal = i < latestParts.length ? latestParts[i] : 0;

        if (currentVal < latestVal) return true; // Ni ishaje
        if (currentVal > latestVal) return false; // Ni nshya kurusha iyari ihari
      }
    } catch (e) {
      return false; // Niba habaye ikosa, mureke akomeze
    }
    return false; // Ni zimwe (Up to date)
  }

  /// 2. KUBARA IMINSI ISIGAYE (5 DAYS DEADLINE)
  /// Ifata itariki version nshya yasohokereyeho (releaseDateStr), ikongeraho iminsi 5.
  /// Igaragaza umubare w'iminsi isigaye (0, 1, 2, 3, 4, cyangwa 5).
  static int getRemainingDays(String releaseDateStr) {
    try {
      // Itariki yasohotseho (Igomba kuba iri mu buryo bwa: "2024-05-20T10:00:00Z")
      DateTime releaseDate = DateTime.parse(releaseDateStr);
      
      // Itariki Ntarengwa (Deadline) = Release Date + 5 Days
      DateTime deadline = releaseDate.add(const Duration(days: 5));
      
      DateTime now = DateTime.now();

      // Difference mu masaha kugira ngo tubone iminsi nyayo
      Duration difference = deadline.difference(now);
      
      int daysLeft = difference.inDays;

      // Niba hasigaye amasaha make ariko atageze ku munsi, bigumye kuri 0 cyangwa 1
      if (difference.isNegative) return 0;
      
      return daysLeft;
    } catch (e) {
      return 5; // Niba itariki yanditse nabi muri RTDB, muhe iminsi 5 y'agaciro
    }
  }
}