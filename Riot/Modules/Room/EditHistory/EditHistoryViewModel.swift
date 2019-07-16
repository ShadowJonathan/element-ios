// File created from ScreenTemplate
// $ createScreen.sh Room/EditHistory EditHistory
/*
 Copyright 2019 New Vector Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation

final class EditHistoryViewModel: EditHistoryViewModelType {

    // MARK: - Constants

    private enum Pagination {
        static let count: UInt = 30
    }

    // MARK: - Properties
    
    // MARK: Private

    private let session: MXSession
    private let aggregations: MXAggregations
    private let formatter: MXKEventFormatter
    private let roomId: String
    private let event: MXEvent
    private let messageFormattingQueue: DispatchQueue

    private var messages: [EditHistoryMessage] = []
    private var operation: MXHTTPOperation?
    private var nextBatch: String?
    private var viewState: EditHistoryViewState?
    
    // MARK: Public

    weak var viewDelegate: EditHistoryViewModelViewDelegate?
    weak var coordinatorDelegate: EditHistoryViewModelCoordinatorDelegate?
    
    // MARK: - Setup
    
    init(session: MXSession,
         formatter: MXKEventFormatter,
         event: MXEvent) {
        self.session = session
        self.aggregations = session.aggregations
        self.formatter = formatter
        self.event = event
        self.roomId = event.roomId
        self.messageFormattingQueue = DispatchQueue(label: "\(type(of: self)).messageFormattingQueue")
    }
    
    // MARK: - Public
    
    func process(viewAction: EditHistoryViewAction) {
        switch viewAction {
        case .loadMore:
            self.loadMoreHistory()
        case .close:
            self.coordinatorDelegate?.editHistoryViewModelDidClose(self)
        }
    }
    
    // MARK: - Private
    
    private func canLoadMoreHistory() -> Bool {
        guard let viewState = self.viewState else {
            return true
        }
        
        let canLoadMoreHistory: Bool
        
        switch viewState {
        case .loading:
            canLoadMoreHistory = false
        case .loaded(sections: _, addedCount: _, allDataLoaded: let allLoaded):
            canLoadMoreHistory = !allLoaded
        default:
            canLoadMoreHistory = true
        }
        
        return canLoadMoreHistory
    }
    
    private func loadMoreHistory() {
        guard self.canLoadMoreHistory() else {
            print("[EditHistoryViewModel] loadMoreHistory: pending loading or all data loaded")
            return
        }
        
        guard self.operation == nil else {
            print("[EditHistoryViewModel] loadMoreHistory: operation already pending")
            return
        }
        
        self.update(viewState: .loading)
        
        self.operation = self.aggregations.replaceEvents(forEvent: self.event.eventId, isEncrypted: self.event.isEncrypted, inRoom: self.roomId, from: self.nextBatch, limit: Pagination.count, success: { [weak self] (response) in
            guard let sself = self else {
                return
            }

            sself.nextBatch = response.nextBatch
            sself.operation = nil

            sself.process(editEvents: response.chunk)

            if response.nextBatch == nil {
                // Append the original event when hitting the end of the edits history
                if let originalEvent = response.originalEvent {
                    sself.process(editEvents: [originalEvent])
                } else {
                    print("[EditHistoryViewModel] loadMoreHistory: The homeserver did not return the original event")
                }
            }
 
        }, failure: { [weak self] error in
                guard let sself = self else {
                    return
                }

                sself.operation = nil
                sself.update(viewState: .error(error))
        })
    }

    private func process(editEvents: [MXEvent]) {
        self.messageFormattingQueue.async {
            
            let newMessages = editEvents.reversed()
                .compactMap { (editEvent) -> EditHistoryMessage? in
                    return self.process(editEvent: editEvent)
            }
            
            let allDataLoaded = self.nextBatch == nil
            let addedCount: Int

            if newMessages.count > 0 {
                self.messages.append(contentsOf: newMessages)
                addedCount = newMessages.count
            } else {
                addedCount = 0
            }
            
            let editHistorySections = self.editHistorySections(from: self.messages)
            
            DispatchQueue.main.async {
                self.update(viewState: .loaded(sections: editHistorySections, addedCount: addedCount, allDataLoaded: allDataLoaded))
            }
        }
    }
    
    private func editHistorySections(from editHistoryMessages: [EditHistoryMessage]) -> [EditHistorySection] {
        
        // Group edit messages by day
        
        let initial: [Date: [EditHistoryMessage]] = [:]
        let dateComponents: Set<Calendar.Component> = [.day, .month, .year]
        let calendar = Calendar.current
        
        let messagesGroupedByDay = editHistoryMessages.reduce(into: initial) { messagesByDay, message in
            let components = calendar.dateComponents(dateComponents, from: message.date)
            if let date = calendar.date(from: components) {
                var messages = messagesByDay[date] ?? []
                messages.append(message)
                messagesByDay[date] = messages
            }
        }
        
        // Create edit sections
        
        var sections: [EditHistorySection] = []
        
        for (date, messages) in messagesGroupedByDay {
            // Sort messages descending (most recent first)
            let sortedMessages = messages.sorted { $0.date.compare($1.date) == .orderedDescending }
            let section = EditHistorySection(date: date, messages: sortedMessages)
            sections.append(section)
        }
        
        // Sort sections descending (most recent first)
        let sortedSections = sections.sorted { $0.date.compare($1.date) == .orderedDescending }
        
        return sortedSections
    }

    private func process(editEvent: MXEvent) -> EditHistoryMessage? {
        // Create a temporary MXEvent that represents this edition
        guard let editedEvent = self.event.editedEvent(fromReplacementEvent: editEvent) else {
            print("[EditHistoryViewModel] processEditEvent: Cannot build edited event: \(editEvent.eventId ?? "")")
            return nil
        }
        
        if editedEvent.isEncrypted && editedEvent.clear == nil {
            if self.session.decryptEvent(editedEvent, inTimeline: nil) == false {
                print("[EditHistoryViewModel] processEditEvent: Fail to decrypt event: \(editedEvent.eventId ?? "")")
            }
        }

        let formatterError = UnsafeMutablePointer<MXKEventFormatterError>.allocate(capacity: 1)
        guard let message = self.formatter.attributedString(from: editedEvent, with: nil, error: formatterError) else {
            print("[EditHistoryViewModel] processEditEvent: cannot format(error: \(formatterError)) edited event: \(editedEvent.eventId ?? "")")
            return nil
        }

        let date = Date(timeIntervalSince1970: TimeInterval(editEvent.originServerTs) / 1000)

        return EditHistoryMessage(date: date, message: message)
    }
    
    private func update(viewState: EditHistoryViewState) {
        self.viewState = viewState
        self.viewDelegate?.editHistoryViewModel(self, didUpdateViewState: viewState)
    }
}
