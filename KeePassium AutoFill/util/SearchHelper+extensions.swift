//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.


import KeePassiumLib
import AuthenticationServices


struct FuzzySearchResults {
    var exactMatch: SearchResults
    var partialMatch: SearchResults
    
    var isEmpty: Bool { return exactMatch.isEmpty && partialMatch.isEmpty }
    
    // True iff the search results contain only one entry, and it is an exact match.
    var hasPerfectMatch: Bool {
        guard partialMatch.isEmpty && (exactMatch.count == 1) else { return false }
        let firstGroup = exactMatch.first!
        return firstGroup.entries.count == 1
    }
}

/// Adds AutoFill-specific search methods
extension SearchHelper {
    
    func find(
        database: Database,
        serviceIdentifiers: [ASCredentialServiceIdentifier]
        ) -> FuzzySearchResults
    {
        var relevantEntries = [ScoredEntry]()
        for si in serviceIdentifiers {
            switch si.type {
            case .domain:
                let partialResults = performSearch(in: database, domain: si.identifier)
                relevantEntries.append(contentsOf: partialResults)
            case .URL:
                let partialResults = performSearch(in: database, url: si.identifier)
                relevantEntries.append(contentsOf: partialResults)
            }
        }
        let exactMatches = relevantEntries.filter { $0.similarityScore >= 0.99 }
        let partialMatches = relevantEntries.filter { $0.similarityScore < 0.99 }
        let searchResults = FuzzySearchResults(
            exactMatch: arrangeByGroups(scoredEntries: exactMatches),
            partialMatch: arrangeByGroups(scoredEntries: partialMatches)
        )
        return searchResults
    }
    
    /// Returns entries that correspond (somewhat) to the given `url`.
    private func performSearch(in database: Database, url: String) -> [ScoredEntry] {
        guard let url = URL.guessFrom(malformedString: url) else { return [] }
        
        var allEntries = [Entry]()
        guard let rootGroup = database.root else { return [] }
        rootGroup.collectAllEntries(to: &allEntries)
        
        // Now just order them by similarity score, and remove unrelated
        let relevantEntries = allEntries
            // exclude non-searchable groups
            .filter { (entry) in
                if let group2 = entry.parent as? Group2 {
                    return group2.isSearchingEnabled ?? true
                } else {
                    return true
                }
            }
            // perform scoring
            .map { (entry) in
                return ScoredEntry(
                    entry: entry,
                    similarityScore: getSimilarity(url: url, entry: entry)
                )
            }
            // remove irrelevant entries
            .filter { $0.similarityScore > 0.0 }
            // most similar first
            .sorted { $0.similarityScore > $1.similarityScore }
        Diag.verbose("Found \(relevantEntries.count) relevant entries [among \(allEntries.count)]")
        return relevantEntries
    }
    
    /// Returns entries that correspond (somewhat) to the given `domain`.
    private func performSearch(in database: Database, domain: String) -> [ScoredEntry] {
        var allEntries = [Entry]()
        guard let rootGroup = database.root else { return [] }
        rootGroup.collectAllEntries(to: &allEntries)
        
        // Now just order them by similarity score, and remove unrelated
        let relevantEntries = allEntries
            // exclude non-searchable groups
            .filter { (entry) in
                if let group2 = entry.parent as? Group2 {
                    return group2.isSearchingEnabled ?? true
                } else {
                    return true
                }
            }
            // perform scoring
            .map { (entry) in
                return ScoredEntry(
                    entry: entry,
                    similarityScore: getSimilarity(domain: domain, entry: entry)
                )
            }
            // remove irrelevant entries
            .filter { $0.similarityScore > 0.0 }
            // most similar first
            .sorted { $0.similarityScore > $1.similarityScore }
        Diag.verbose("Found \(relevantEntries.count) relevant entries [among \(allEntries.count)]")
        return relevantEntries
    }

    
    // MARK: - Similarity scoring methods
    
    private func howSimilar(domain: String, with url: URL?) -> Double {
        guard let host = url?.host?.localizedLowercase else { return 0.0 }
        
        if host == domain {
            return 1.0
        }
        if host.hasSuffix("." + domain) {
            // host is a subdomain of `domain`
            return 0.9
        }
        return 0.0
    }
    
    /// Returns a similarity score of the given `domain` in the given `entry`.
    private func getSimilarity(domain: String, entry: Entry) -> Double {
        let urlScore = howSimilar(domain: domain, with: URL.guessFrom(malformedString: entry.url))
        let titleScore = entry.title.localizedCaseInsensitiveContains(domain) ? 0.8 : 0.0
        let notesScore = entry.notes.localizedCaseInsensitiveContains(domain) ? 0.5 : 0.0
        
        if let entry2 = entry as? Entry2 {
            // Entry 2
            let altURLScore = howSimilar(
                domain: domain,
                with: URL.guessFrom(malformedString: entry2.overrideURL))
            let maxScoreSoFar = max(urlScore, titleScore, notesScore, altURLScore)
            if maxScoreSoFar >= 0.5 {
                // further checks won't improve the score, so let's save our time
                return maxScoreSoFar
            }
            
            // check custom fields
            let extraFieldScores: [Double] = entry2.fields
                .filter { !$0.isStandardField }
                .map { (field) in
                    return field.value.localizedCaseInsensitiveContains(domain) ? 0.5 : 0.0
            }
            return max(maxScoreSoFar, extraFieldScores.max() ?? 0.0)
        } else {
            // Entry 1
            return max(urlScore, titleScore, notesScore)
        }
    }
    
    
    /// Estimates similarity score between two URLs.
    /// - Same URL -> 1.0
    /// - Same hosts -> 0.7
    /// - Same hosts and partially paths -> 0.7 ÷ 1.0
    /// - Same second level domain names -> 0.5  ('www.example.com' vs 'auth.example.com')
    private func howSimilar(_ url1: URL, with url2: URL?) -> Double {
        guard let url2 = url2 else { return 0.0 }
        
        if url1 == url2 { return 1.0 }
        
        guard let host1 = url1.host?.localizedLowercase,
            let host2 = url2.host?.localizedLowercase else { return 0.0 }
        if host1 == host2 {
            // equal hosts -> already 0.7
            // but let's also take into account similarity of the path components
            
            guard url2.path.isNotEmpty else { return 0.7 }
            let lowercasePath1 = url1.path.localizedLowercase
            let lowercasePath2 = url2.path.localizedLowercase
            let commonPrefixCount = Double(lowercasePath1.commonPrefix(with: lowercasePath2).count)
            let maxPathCount = Double(max(lowercasePath1.count, lowercasePath2.count))
            let pathSimilarity = commonPrefixCount / maxPathCount // [0.0 ÷ 1.0]
            return 0.7 + 0.3 * pathSimilarity // 0.3 to ensure the result is within [0.7 ÷ 1.0]
        } else {
            // somewhat similar hosts?
            if url1.domain2 == url2.domain2 {
                return 0.5
            }
        }
        return 0.0
    }
    
    private func getSimilarity(url: URL, entry: Entry) -> Double {
        // General similarity conditions:
        // - `url` is similar to entry.URL -> (0.7, 1)
        // - `url.host` occurs inside `entry.title` -> 0.8
        // - `url.host` occurs inside `entry.notes` -> 0.5
        // For Entry2:
        // - `url` is similar to `entry.overrideURL` -> (0.7, 1)
        // - `url.host` occurs inside custom field values -> 0.6
        
        // is entry URL similar to the `url`?
        let urlScore = howSimilar(url, with: URL.guessFrom(malformedString: entry.url))
        // does `url.host` occure inside entry title or notes?
        let titleScore: Double
        let notesScore: Double
        
        if let urlHost = url.host, let urlDomain2 = url.domain2 {
            if entry.title.localizedCaseInsensitiveContains(urlHost) {
                titleScore = 0.8
            } else if entry.title.localizedCaseInsensitiveContains(urlDomain2) {
                titleScore = 0.5
            } else {
                titleScore = 0.0
            }
            if entry.notes.localizedCaseInsensitiveContains(urlHost) {
                notesScore = 0.5
            } else if entry.notes.localizedCaseInsensitiveContains(urlDomain2) {
                notesScore = 0.3
            } else {
                notesScore = 0.0
            }
        } else {
            titleScore = 0.0
            notesScore = 0.0
        }
        
        if let entry2 = entry as? Entry2 {
            // Entry 2
            let altURLScore = howSimilar(
                url,
                with: URL.guessFrom(malformedString: entry2.overrideURL))
            let maxScoreSoFar = max(urlScore, titleScore, notesScore, altURLScore)
            if maxScoreSoFar >= 0.5 {
                // further checks won't improve the score, so let's save our time
                return maxScoreSoFar
            }
            
            // check custom fields
            let urlString = url.absoluteString
            guard let urlHost = url.host,
                let urlDomain2 = url.domain2 else { return maxScoreSoFar }
            let extraFieldScores: [Double] = entry2.fields
                .filter { !$0.isStandardField }
                .map { (field) in
                    if field.value.localizedCaseInsensitiveContains(urlString) {
                        return 1.0
                    } else if field.value.localizedCaseInsensitiveContains(urlHost) {
                        return 0.5
                    } else if field.value.localizedCaseInsensitiveContains(urlDomain2) {
                        return 0.3
                    } else {
                        return 0.0
                    }
            }
            return max(maxScoreSoFar, extraFieldScores.max() ?? 0.0)
        } else {
            // Entry 1
            return max(urlScore, titleScore, notesScore)
        }
    }
}

fileprivate extension URL {
    /// Creates a URL from a potentially ill-formed string (such as host-only)
    static func guessFrom(malformedString string: String?) -> URL? {
        guard let string = string else { return nil }
        
        if let wellFormedURL = URL(string: string), let _ = wellFormedURL.scheme {
            // parsed and has non-empty scheme => considered OK
            return wellFormedURL
        }
        // there was no scheme, try a fake one
        guard let fakeSchemeURL = URL(string: "https://" + string),
            let _ = fakeSchemeURL.host else {
                // no host even with fake scheme => cannot do anything else
                return nil
        }
        return fakeSchemeURL
    }
}
