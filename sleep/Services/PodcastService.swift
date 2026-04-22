//
//  PodcastService.swift
//  sleep
//
//  Apple has no first-party Podcasts SDK, so this service talks to:
//    1. iTunes Search API (https://itunes.apple.com/search?media=podcast)
//       — free, no auth — to find podcasts by keyword.
//    2. Each podcast's RSS feed — parsed with XMLParser — to list episodes.
//
//  Playback itself is handled by MediaPlaybackService via AVPlayer, because
//  podcast episodes are plain mp3/m4a streams.
//

import Foundation
import os

// MARK: - Models

struct PodcastShow: Identifiable, Hashable, Sendable {
    let id: Int                // iTunes collectionId
    let name: String           // collectionName
    let artist: String         // artistName
    let artworkURL: URL?       // artworkUrl600
    let feedURL: URL           // feedUrl
}

struct PodcastEpisode: Identifiable, Hashable, Sendable {
    let id: String             // guid
    let title: String
    let pubDate: Date?
    let duration: TimeInterval?
    let audioURL: URL          // enclosure url
    let showName: String
    let artworkURL: URL?
}

// MARK: - Errors

enum PodcastError: LocalizedError {
    case networkFailure(underlying: Error)
    case badResponse
    case malformedFeed

    var errorDescription: String? {
        switch self {
        case .networkFailure(let e): "Network error: \(e.localizedDescription)"
        case .badResponse: "Unexpected response from podcast directory."
        case .malformedFeed: "This podcast's feed could not be read."
        }
    }
}

// MARK: - Service

@Observable
@MainActor
final class PodcastService {

    // MARK: - Cache (10 minutes)

    private struct CachedSearch {
        let results: [PodcastShow]
        let timestamp: Date
    }
    private struct CachedFeed {
        let episodes: [PodcastEpisode]
        let timestamp: Date
    }

    private var searchCache: [String: CachedSearch] = [:]
    private var feedCache: [URL: CachedFeed] = [:]
    private let cacheLifetime: TimeInterval = 600 // 10 min

    // MARK: - Search

    /// Search the iTunes Podcast directory. Free, no auth required.
    func search(_ query: String) async throws -> [PodcastShow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let cached = searchCache[trimmed.lowercased()],
           Date().timeIntervalSince(cached.timestamp) < cacheLifetime {
            return cached.results
        }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "entity", value: "podcast"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "term", value: trimmed)
        ]
        guard let url = components.url else { return [] }

        AppLogger.sound.info("🎙️ Podcast search: \(trimmed)")
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            AppLogger.sound.error("Podcast search network error: \(error.localizedDescription)")
            throw PodcastError.networkFailure(underlying: error)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw PodcastError.badResponse
        }

        let shows: [PodcastShow] = results.compactMap { dict in
            guard let id = dict["collectionId"] as? Int,
                  let name = dict["collectionName"] as? String,
                  let feedString = dict["feedUrl"] as? String,
                  let feedURL = URL(string: feedString) else { return nil }
            let artist = (dict["artistName"] as? String) ?? ""
            let artworkString = (dict["artworkUrl600"] as? String)
                ?? (dict["artworkUrl100"] as? String)
            let artwork = artworkString.flatMap(URL.init(string:))
            return PodcastShow(id: id, name: name, artist: artist, artworkURL: artwork, feedURL: feedURL)
        }

        searchCache[trimmed.lowercased()] = CachedSearch(results: shows, timestamp: Date())
        AppLogger.sound.info("🎙️ Podcast search returned \(shows.count) results")
        return shows
    }

    // MARK: - Episodes

    /// Fetch and parse the RSS feed for a podcast, returning recent episodes.
    func episodes(for show: PodcastShow, limit: Int = 15) async throws -> [PodcastEpisode] {
        if let cached = feedCache[show.feedURL],
           Date().timeIntervalSince(cached.timestamp) < cacheLifetime {
            return Array(cached.episodes.prefix(limit))
        }

        AppLogger.sound.info("🎙️ Fetching RSS feed: \(show.feedURL.absoluteString)")
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: show.feedURL)
        } catch {
            throw PodcastError.networkFailure(underlying: error)
        }

        let parser = RSSParser(showName: show.name, showArtwork: show.artworkURL)
        guard let episodes = parser.parse(data: data) else {
            throw PodcastError.malformedFeed
        }

        feedCache[show.feedURL] = CachedFeed(episodes: episodes, timestamp: Date())
        AppLogger.sound.info("🎙️ Parsed \(episodes.count) episodes from \(show.name)")
        return Array(episodes.prefix(limit))
    }
}

// MARK: - RSS Parser

private final class RSSParser: NSObject, XMLParserDelegate {

    private let showName: String
    private let showArtwork: URL?

    init(showName: String, showArtwork: URL?) {
        self.showName = showName
        self.showArtwork = showArtwork
    }

    private var episodes: [PodcastEpisode] = []
    private var currentElement = ""
    private var currentCharacters = ""
    private var inItem = false

    // Per-item accumulators
    private var itemTitle = ""
    private var itemGUID = ""
    private var itemPubDate = ""
    private var itemDuration = ""
    private var itemEnclosureURL: URL?

    private lazy var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return df
    }()

    func parse(data: Data) -> [PodcastEpisode]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return episodes
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentCharacters = ""
        if elementName == "item" {
            inItem = true
            itemTitle = ""; itemGUID = ""; itemPubDate = ""
            itemDuration = ""; itemEnclosureURL = nil
        }
        if elementName == "enclosure", inItem,
           let urlString = attributeDict["url"], let url = URL(string: urlString) {
            itemEnclosureURL = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentCharacters += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard inItem else { return }
        let trimmed = currentCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title": if itemTitle.isEmpty { itemTitle = trimmed }
        case "guid": itemGUID = trimmed
        case "pubDate": itemPubDate = trimmed
        case "itunes:duration", "duration": itemDuration = trimmed
        case "item":
            if let audio = itemEnclosureURL {
                let pubDate = dateFormatter.date(from: itemPubDate)
                let duration = parseDuration(itemDuration)
                let id = itemGUID.isEmpty ? audio.absoluteString : itemGUID
                episodes.append(PodcastEpisode(
                    id: id,
                    title: itemTitle,
                    pubDate: pubDate,
                    duration: duration,
                    audioURL: audio,
                    showName: showName,
                    artworkURL: showArtwork
                ))
            }
            inItem = false
        default: break
        }
    }

    private func parseDuration(_ raw: String) -> TimeInterval? {
        // Handles "HH:MM:SS", "MM:SS", or raw seconds "3600"
        if let seconds = TimeInterval(raw) { return seconds }
        let parts = raw.split(separator: ":").compactMap { TimeInterval($0) }
        switch parts.count {
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return parts[0] * 60 + parts[1]
        default: return nil
        }
    }
}
