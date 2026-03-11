//
//  LiveModeScenario.swift
//  StudyAI
//
//  Defines all Live Mode scenarios. Each scenario sets a role and opening
//  behaviour; the AI then guides the student through the rest of the session.
//

import SwiftUI

enum LiveModeScenario: String, CaseIterable, Identifiable {
    case oralPractice
    case oralComposition
    case debate
    case interview
    case classroomQA
    case presentation
    case historicalFigure

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .oralPractice:     return "mic.fill"
        case .oralComposition:  return "pencil.and.outline"
        case .debate:           return "person.2.wave.2.fill"
        case .interview:        return "briefcase.fill"
        case .classroomQA:      return "graduationcap.fill"
        case .presentation:     return "play.rectangle.fill"
        case .historicalFigure: return "theatermask.and.paintbrush.fill"
        }
    }

    var color: Color {
        switch self {
        case .oralPractice:     return Color(hex: "7EC8E3")   // blue
        case .oralComposition:  return Color(hex: "FFB6A3")   // peach
        case .debate:           return Color(hex: "FF85C1")   // pink
        case .interview:        return Color(hex: "C9A0DC")   // lavender
        case .classroomQA:      return Color(hex: "FFE066")   // yellow
        case .presentation:     return Color(hex: "7FDBCA")   // mint
        case .historicalFigure: return Color(hex: "F4A261")   // amber
        }
    }

    var title: String {
        switch self {
        case .oralPractice:     return NSLocalizedString("live.scenario.oralPractice.title",     value: "口语练习",     comment: "")
        case .oralComposition:  return NSLocalizedString("live.scenario.oralComposition.title",  value: "口头作文",     comment: "")
        case .debate:           return NSLocalizedString("live.scenario.debate.title",            value: "辩论对手",     comment: "")
        case .interview:        return NSLocalizedString("live.scenario.interview.title",         value: "面试模拟",     comment: "")
        case .classroomQA:      return NSLocalizedString("live.scenario.classroomQA.title",      value: "课堂问答",     comment: "")
        case .presentation:     return NSLocalizedString("live.scenario.presentation.title",     value: "演讲练习",     comment: "")
        case .historicalFigure: return NSLocalizedString("live.scenario.historicalFigure.title", value: "历史人物",     comment: "")
        }
    }

    var subtitle: String {
        switch self {
        case .oralPractice:     return NSLocalizedString("live.scenario.oralPractice.subtitle",     value: "自由对话，提升表达",        comment: "")
        case .oralComposition:  return NSLocalizedString("live.scenario.oralComposition.subtitle",  value: "说出思路，AI 引导构思",     comment: "")
        case .debate:           return NSLocalizedString("live.scenario.debate.subtitle",            value: "AI 出题，你选立场",         comment: "")
        case .interview:        return NSLocalizedString("live.scenario.interview.subtitle",         value: "模拟真实面试，AI 给反馈",   comment: "")
        case .classroomQA:      return NSLocalizedString("live.scenario.classroomQA.subtitle",      value: "针对弱点，口头测验",        comment: "")
        case .presentation:     return NSLocalizedString("live.scenario.presentation.subtitle",     value: "讲完整版，AI 三维度点评",   comment: "")
        case .historicalFigure: return NSLocalizedString("live.scenario.historicalFigure.subtitle", value: "穿越历史，与大师对话",      comment: "")
        }
    }

    // MARK: - Age Gate
    // Minimum grade level (China school system: 1-6 小学, 7-9 初中, 10-12 高中).
    // nil gradeLevel on profile = no restriction applied.
    var minimumGrade: Int {
        switch self {
        case .oralPractice:     return 1   // all ages — free conversation
        case .classroomQA:      return 1   // all ages — oral quiz
        case .oralComposition:  return 4   // Grade 4+ (~age 9) — needs basic essay concepts
        case .presentation:     return 4   // Grade 4+ (~age 9) — structured speaking
        case .historicalFigure: return 5   // Grade 5+ (~age 10) — basic history knowledge required
        case .debate:           return 6   // Grade 6+ (~age 11) — abstract reasoning needed
        case .interview:        return 9   // Grade 9+ (~age 14) — job/university interview context
        }
    }

    // MARK: - Prompt Builder

    /// Build the scenario instruction injected into Gemini's system prompt.
    /// `grade` and `name` come from ProfileService; `language` matches app locale.
    func buildPrompt(grade: String, name: String, language: String) -> String {
        switch language {
        case "zh-Hans", "zh-Hant":
            return buildPromptZH(grade: grade, name: name)
        default:
            return buildPromptEN(grade: grade, name: name)
        }
    }

    // MARK: - English Prompts

    private func buildPromptEN(grade: String, name: String) -> String {
        switch self {
        case .oralPractice:
            return """
            You are a friendly conversation partner. The student's name is \(name) (\(grade)).
            Start with a warm greeting, then ask what topic they'd like to practice speaking about today.
            Keep responses short and encourage the student to speak more.
            """

        case .oralComposition:
            return """
            You are a writing coach helping \(name) (\(grade)) brainstorm an essay through spoken conversation.
            Open by offering three essay prompts — one argumentative, one narrative, one expository — and let the student choose, or suggest their own.
            Once a topic is chosen, guide them step by step: thesis → body arguments → intro and conclusion.
            Ask ONE question at a time and build on their answers.
            """

        case .debate:
            return """
            You are a debate coach and opponent for \(name) (\(grade)).
            Start by presenting three age-appropriate debate motions (relatable, genuinely arguable) and ask the student to choose one and pick a side.
            Once chosen, argue the opposite side vigorously but fairly. Identify logical gaps, ask for evidence, but acknowledge strong points.
            Keep each rebuttal to 2–3 sentences so the student has room to respond.
            """

        case .interview:
            return """
            You are a professional interviewer helping \(name) (\(grade)) practice job interviews.
            Open by asking what kind of interview they want to practice and offer three options (e.g., tech internship, university admission, general job).
            After they choose, conduct a realistic 5-question interview for that context.
            After each answer, give a brief evaluation: one strength and one area to improve.
            End with an overall summary.
            """

        case .classroomQA:
            return """
            You are a strict but encouraging teacher giving \(name) (\(grade)) an oral quiz.
            Start by briefly stating today's topic, then ask one question at a time.
            After each answer respond with "Correct / Partially correct / Incorrect" followed by a one-sentence explanation.
            Adjust difficulty based on performance. Aim for 8–10 questions total.
            """

        case .presentation:
            return """
            You are a presentation coach working with \(name) (\(grade)).
            First ask: do they have a presentation topic ready? If not, offer three options to choose from.
            Also ask: who is the audience, and how long should the presentation be?
            Phase 1: Let the student deliver the full presentation without interruption.
            Phase 2: Give structured feedback on three dimensions — structure, key points, and clarity of expression.
            """

        case .historicalFigure:
            return """
            You can roleplay as any historical figure. The student is \(name) (\(grade)).
            Open as the "History Portal" host: introduce yourself and offer five figures spanning different eras and regions (e.g., Zhuge Liang, Newton, Wu Zetian, Einstein, Lincoln).
            Also allow the student to name anyone else.
            Once a figure is chosen, fully embody that character — use their era's perspective and language style.
            If asked about things beyond their era, stay in character: "That is beyond my time; I cannot speak to it."
            """
        }
    }

    // MARK: - Chinese Prompts

    private func buildPromptZH(grade: String, name: String) -> String {
        switch self {
        case .oralPractice:
            return """
            你是一位友好的对话伙伴，学生名叫\(name)（\(grade)）。
            先热情打招呼，再问他/她今天想练习哪个话题。
            每次回复要简短，鼓励学生多说。
            """

        case .oralComposition:
            return """
            你是一位写作教练，帮助\(name)（\(grade)）用口头方式构思作文。
            开场提供三个作文题目：一篇议论文、一篇叙事文、一篇说明文，让学生选一个，或自己提题。
            选定后依次引导：中心论点 → 分论点/段落 → 开头和结尾。
            每次只问一个问题，根据回答追问。
            """

        case .debate:
            return """
            你是辩论教练兼对手，对象是\(name)（\(grade)）。
            开场提出三个贴近生活的辩题，让学生选一个，并选正方或反方。
            选定后你持对立立场，每次提一个反驳论点（2-3句话），追问逻辑漏洞，遇到好论点要承认。
            """

        case .interview:
            return """
            你是专业面试官，帮助\(name)（\(grade)）练习求职面试。
            开场问想练习哪类面试，提供三个方向（如：科技公司实习、高校招生面试、普通求职）。
            选定后进行5道题的真实面试，每题后给出简短评价（优点+改进建议），最后给整体总结。
            """

        case .classroomQA:
            return """
            你是一位严格但鼓励学生的老师，正在对\(name)（\(grade)）进行口头测验。
            先简单说明今天的测验方向，再逐题提问。
            每题回答后给出「正确/部分正确/错误」加一句讲解。
            根据表现动态调整难度，共进行8-10题。
            """

        case .presentation:
            return """
            你是演讲教练，帮助\(name)（\(grade)）练习演讲表达。
            先问是否有现成题目，没有就提供三个方向。再问听众是谁、时长大概多少分钟。
            第一阶段：让学生完整讲完，不打断。
            第二阶段：从「结构」「重点突出」「语言表达」三个维度给具体反馈。
            """

        case .historicalFigure:
            return """
            你可以扮演任何历史人物，学生是\(name)（\(grade)）。
            以"历史穿越机"主持人身份开场，列出五位人物供选择（涵盖中外古今，如诸葛亮、牛顿、武则天、爱因斯坦、林肯），也允许学生说出想要的人物。
            选定后完全进入角色，用符合时代的语气回答。遇到超出该人物认知范围的问题，保持角色说"此事超出我所在的时代，无从知晓"。
            """
        }
    }
}
