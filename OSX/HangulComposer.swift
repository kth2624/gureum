//
//  HangulComposer.swift
//  Gureum
//
//  Created by Jeong YunWon on 2018. 8. 13..
//  Copyright © 2018년 youknowone.org. All rights reserved.
//

import Foundation
import Hangul

let DEBUG_HANGULCOMPOSER = false

class HangulComposerCombination {
    /*!
     @brief  설정에 따라 조합 완료할 문자 최종처리
     */
    public class func commitString(ucsString: UnsafePointer<HGUCSChar>) -> String {
        return NSString.stringByRemovingFillerWithUCSString(ucsString) as String
    }

    /*!
     @brief  설정에 따라 조합중으로 보여줄 문자 최종처리
     */
    public class func composedString(ucsString: UnsafePointer<HGUCSChar>) -> String {
        return NSString.stringByRemovingFillerWithUCSString(ucsString) as String
    }
}

/*!
 @brief  libhangul을 사용하는 합성기

 libhangul의 input context를 사용하는 합성기이다. -init 로는 두벌식 합성기가 설정된다.

 @coclass HGInputContext
 */
@objcMembers public class HangulComposer: NSObject, CIMComposerDelegate {
    let inputContext: HGInputContext
    var _commitString: String
    let configuration = GureumConfiguration.shared

    init?(keyboardIdentifier: String) {
        self._commitString = String()
        guard let inputContext = HGInputContext(keyboardIdentifier: keyboardIdentifier) else {
            return nil
        }
        self.inputContext = inputContext
        self.inputContext.setOption(HANGUL_IC_OPTION_AUTO_REORDER, value: configuration.hangulAutoReorder)
        self.inputContext.setOption(HANGUL_IC_OPTION_NON_CHOSEONG_COMBI, value: configuration.hangulNonChoseongCombination)
        super.init()
        configuration.addObserver(self, forKeyPath: GureumConfigurationName.hangulAutoReorder.rawValue, options: NSKeyValueObservingOptions.new, context: nil)
        configuration.addObserver(self, forKeyPath: GureumConfigurationName.hangulNonChoseongCombination.rawValue, options: NSKeyValueObservingOptions.new, context: nil)
        configuration.addObserver(self, forKeyPath: GureumConfigurationName.hangulForceStrictCombinationRule.rawValue, options: NSKeyValueObservingOptions.new, context: nil)
    }

    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == GureumConfigurationName.hangulForceStrictCombinationRule.rawValue {
            let keyboard = GureumInputSourceIdentifier(rawValue: configuration.lastHangulInputMode)?.keyboardIdentifier ?? "2"
            self.setKeyboard(identifier: keyboard)
        } else {
            self.inputContext.setOption(HANGUL_IC_OPTION_AUTO_REORDER, value: configuration.hangulAutoReorder)
            self.inputContext.setOption(HANGUL_IC_OPTION_NON_CHOSEONG_COMBI, value: configuration.hangulNonChoseongCombination)
        }
    }

    deinit {
        configuration.removeObserver(self, forKeyPath: GureumConfigurationName.hangulAutoReorder.rawValue)
        configuration.removeObserver(self, forKeyPath: GureumConfigurationName.hangulNonChoseongCombination.rawValue)
        configuration.removeObserver(self, forKeyPath: GureumConfigurationName.hangulForceStrictCombinationRule.rawValue)
    }

    /*!
     @brief  현재 context의 배열을 바꾼다.
     @param  identifier  libhangul의 @ref hangul_ic_select_keyboard 를 참고한다.
     */
    public func setKeyboard(identifier: String) {
        if configuration.hangulForceStrictCombinationRule && (identifier == "39" || identifier == "3f") {
            let strictCombinationIdentifier = "\(identifier)s"
            self.inputContext.setKeyboardWithIdentifier(strictCombinationIdentifier)
        } else {
            self.inputContext.setKeyboardWithIdentifier(identifier)
        }
    }

    public var commitString: String {
        get{
            return self._commitString;
        }
    }

    // CIMComposerDelegate

    public func input(controller: CIMInputController, inputText string: String?, key keyCode: Int, modifiers flags: NSEvent.ModifierFlags, client sender: Any) -> CIMInputTextProcessResult {
        // libhangul은 backspace를 키로 받지 않고 별도로 처리한다.
        if (keyCode == kVK_Delete) {
            return self.inputContext.backspace() ? CIMInputTextProcessResult.processed : CIMInputTextProcessResult.notProcessed
        }

        if (keyCode > 50 || keyCode == kVK_Delete || keyCode == kVK_Return || keyCode == kVK_Tab || keyCode == kVK_Space) {
            dlog(DEBUG_HANGULCOMPOSER, " ** ESCAPE from outbound keyCode: %lu", keyCode);
            return CIMInputTextProcessResult.notProcessedAndNeedsCommit;
        }

        var string = string!
        // 한글 입력에서 캡스락 무시
        if flags.contains(.capsLock) {
            if !flags.contains(.shift) {
                string = string.lowercased();
            }
        }
        let handled = self.inputContext.process(string.first!.unicodeScalars.first!.value)
        let UCSString = self.inputContext.commitUCSString
        let recentCommitString = HangulComposerCombination.commitString(ucsString: UCSString)
        if configuration.hangulWonCurrencySymbolForBackQuote && keyCode == kVK_ANSI_Grave && flags.isSubset(of: .capsLock) {
            if !handled {
                self._commitString += recentCommitString + "₩"
                return CIMInputTextProcessResult.processed
            } else if recentCommitString.last! == "`" {
                self._commitString += recentCommitString.dropLast() + "₩"
                return CIMInputTextProcessResult.processed
            }
        }

        self._commitString += recentCommitString
        // dlog(DEBUG_HANGULCOMPOSER, @"HangulComposer -inputText: string %@ (%@ added)", self->_commitString, recentCommitString);
        return handled ? .processed : .notProcessedAndNeedsCancel;
    }

    public func input(controller: CIMInputController, command string: String?, key keyCode: Int, modifiers flags: NSEvent.ModifierFlags, client sender: Any) -> CIMInputTextProcessResult {
        assert(false)
        return .notProcessed;
    }

    public var composedString: String {
        get {
            let preedit = self.inputContext.preeditUCSString
            return HangulComposerCombination.composedString(ucsString: preedit)
        }
    }

    public var originalString: String {
        get {
            let preedit = self.inputContext.preeditUCSString
            return HangulComposerCombination.commitString(ucsString: preedit)
        }
    }

    public func dequeueCommitString() -> String {
        let queuedCommitString = self._commitString
        self._commitString = ""
        return queuedCommitString
    }

    public func cancelComposition() {
        let flushedString: String! = HangulComposerCombination.commitString(ucsString: self.inputContext.flushUCSString())
        self._commitString += flushedString
    }

    public func clearContext() {
        self.inputContext.reset()
        self._commitString = ""
    }

    public var hasCandidates: Bool {
        get {
            return false
        }
    }

    #if DEBUG
    public func candidateSelected(_ candidateString: NSAttributedString) {
        assert(false)
    }

    public func candidateSelectionChanged(_ candidateString: NSAttributedString) {
        assert(false)
    }
    #endif
}

extension NSString {
    @objc class func stringByRemovingFillerWithUCSString(_ ucsString: UnsafePointer<HGUCSChar>) -> NSString {
        // 채움문자로 조합 중 판별
        if !HGCharacterIsChoseong(ucsString[0]) {
            return NSString(ucsString: ucsString)
        }
        if ucsString[0] == 0x115f {
            if ucsString[0] == 0x115f {
                let trans: [Int:Int]=[
                    //{'ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'}
                    0x3131: 0x1100, 0x3132: 0x1101, 0x3134: 0x1102, 0x3137: 0x1103, 0x3138: 0x1104, 0x3139: 0x1105, 0x3141: 0x1106, 0x3142: 0x1107, 0x3143: 0x1108, 0x3145: 0x1109, 0x3146: 0x110A, 0x3147: 0x110B, 0x3148: 0x110C, 0x3149: 0x110D, 0x314a:0x110E , 0x314b: 0x110F, 0x314c:0x1110, 0x314d: 0x1111, 0x314e: 0x1112,
                    //{'ㅏ', 'ㅐ', 'ㅑ', 'ㅒ', 'ㅓ', 'ㅔ', 'ㅕ', 'ㅖ', 'ㅗ', 'ㅘ', 'ㅙ', 'ㅚ', 'ㅛ', 'ㅜ', 'ㅝ', 'ㅞ', 'ㅟ', 'ㅠ', 'ㅡ', 'ㅢ', 'ㅣ'}
                    0x314f:0x1161, 0x3150:0x1162, 0x3151:0x1163, 0x3152:0x1164, 0x3153:0x1165, 0x3154:0x1166, 0x3155:0x1167, 0x3156:0x1168, 0x3157:0x1169, 0x3158:0x116A, 0x3159:0x116B, 0x315a:0x116C, 0x315b:0x116D, 0x315c:0x116E, 0x315d:0x116F, 0x315e:0x1170, 0x315f:0x1171, 0x3160:0x1172, 0x3161:0x1173, 0x3162:0x1174, 0x3163:0x1175]
                
                //if ucsString[1] ==
                
                return NSString(ucsString: ucsString + 1)
            }
            return NSString(ucsString: ucsString + 1)
        }
        /* if (UCSString[1] == 0x1160) */
        let fill: NSMutableString = NSMutableString(ucsString: ucsString, length: 1)
        fill.append(NSString(ucsString: ucsString + 2, length: 1) as String)
        return fill
    }
}
