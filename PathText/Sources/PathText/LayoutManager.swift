//
//  LayoutManager.swift
//  
//
//  Created by Rob Napier on 1/5/20.
//

import Foundation
import CoreGraphics
import CoreText
import UIKit

struct PathTextLayoutManager {
    public var text: NSAttributedString = NSAttributedString() {
        didSet {
            invalidateGlyphs()
        }
    }

    public var path: CGPath = CGMutablePath() {
        didSet {
            invalidateLayout()
        }
    }

    public var typographicBounds: CGRect {
        // FIXME: ensureLayout? Maybe pre-calculate this?
        glyphRuns.reduce(.null) { $0.union($1.typographicBounds) }
    }

    mutating func ensureGlyphs() {
        if needsGlyphGeneration { updateGlyphs() }
    }

    mutating func ensureLayout() {
        if needsLayout { updateLayout() }
    }

    private var needsGlyphGeneration = false
    public mutating func invalidateGlyphs() { needsGlyphGeneration = true }

    private var needsLayout = false
    public mutating func invalidateLayout() { needsLayout = true }

    private var glyphRuns: [GlyphRun] = []

    private mutating func updateGlyphs() {
        let line = CTLineCreateWithAttributedString(text)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]

        glyphRuns = runs.map { run in
            let glyphCount = CTRunGetGlyphCount(run)

            let positions: [CGPoint] = Array(unsafeUninitializedCapacity: glyphCount) { (buffer, initialized) in
                CTRunGetPositions(run, CFRange(), buffer.baseAddress!)
                initialized = glyphCount
            }

            let glyphs = Array<CGGlyph>(unsafeUninitializedCapacity: glyphCount) { (buffer, initialized) in
                CTRunGetGlyphs(run, CFRange(), buffer.baseAddress!)
                initialized = glyphCount
            }

            let locations: [GlyphBoxes] = (0..<glyphCount).map { i in
                GlyphBoxes(run: run, index: i, glyph: glyphs[i], position: positions[i])
            }
            .sorted { $0.anchor < $1.anchor }

            return GlyphRun(run: run, boxes: locations)
        }

        needsGlyphGeneration = false
    }

    private mutating func updateLayout() {
        ensureGlyphs()
        
        let runsLength = glyphRuns.last?.boxes.last?.bounds.maxX ?? 0
        let pathLength = path.length
        let extraSpace = pathLength - runsLength
        let glyphsCount = glyphRuns.reduce(into: .zero) { $0 += $1.boxes.count }
        let extraSpacePerGlyph = extraSpace / CGFloat(glyphsCount - 1)

        var tangents = TangentGenerator(path: path)
        glyphRuns = glyphRuns.map {
            var glyphRun = $0
            let paragraphStyle = glyphRun.attributes[.paragraphStyle] as? NSParagraphStyle

            func offset(at index: Int) -> CGFloat {
                if let paragraphStyle {
                    switch paragraphStyle.alignment {
                    case .left:
                        return 0
                    case .right:
                        return extraSpace
                    case .center:
                        return extraSpace / 2
                    case .justified:
                        return extraSpacePerGlyph * CGFloat(index)
                    case .natural:
                        if CTRunGetStatus(glyphRun.run).contains(.rightToLeft) {
                            return extraSpace
                        } else {
                            return 0
                        }
                    @unknown default:
                        return 0
                    }
                } else {
                    return 0
                }
            }

            glyphRun.updateTangents(with: &tangents, offset: offset(at:))
            return glyphRun
        }

        needsLayout = false
    }

    public mutating func draw(in context: CGContext) {
        ensureLayout()

        for run in glyphRuns {
            run.draw(in: context)
        }
    }
}
