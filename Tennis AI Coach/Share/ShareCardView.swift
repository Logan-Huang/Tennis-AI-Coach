//
//  ShareCardView.swift
//  Tennis AI Coach
//
//  1080×1350 share cards rendered with ImageRenderer. The best-shot frame
//  carries the skeleton — the visible differentiator no competitor shows.
//  Copy is honest: "form score", never speed claims.
//

import SwiftUI

/// Fixed pixel canvas for social sharing (4:5 portrait).
enum ShareCardMetrics {
    static let size = CGSize(width: 1080, height: 1350)
}

struct SessionShareCard: View {
    let session: SessionScore
    let headline: String
    let date: Date
    /// Best-shot frame with the skeleton already drawn on it.
    let frame: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            header
            frameSection
            footer
        }
        .frame(width: ShareCardMetrics.size.width, height: ShareCardMetrics.size.height)
        .background(Color(red: 0.06, green: 0.30, blue: 0.21))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                Text("SESSION SCORE")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.7))
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 28) {
                    shareStat("BEST", session.best)
                    shareStat("AVG", session.average)
                    shareStat("WORST", session.worst)
                }
            }
            Spacer()
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: session.overall.isFinite ? max(0.02, session.overall / 100) : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Fmt.score(session.overall))
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 240, height: 240)
        }
        .padding(56)
    }

    private func shareStat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 6) {
            Text(Fmt.score(value))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 22, weight: .semibold))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private var frameSection: some View {
        if let frame {
            Image(uiImage: frame)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: ShareCardMetrics.size.width, height: 760)
                .clipped()
        } else {
            Rectangle()
                .fill(Color(red: 0.10, green: 0.44, blue: 0.30))
                .frame(height: 760)
                .overlay {
                    Image(systemName: "figure.tennis")
                        .font(.system(size: 160))
                        .foregroundStyle(.white.opacity(0.25))
                }
        }
    }

    private var footer: some View {
        HStack {
            Text(headline)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 32)
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(red: 0.855, green: 0.925, blue: 0.286))
                    .frame(width: 28, height: 28)
                Text("Tennis AI Coach")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 56)
        .frame(maxHeight: .infinity)
    }
}
