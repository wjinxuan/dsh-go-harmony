import { DshQuestionRequest, DshQuestionAnswer, DshQuestion } from '../dsh/DshWire';

export interface QuestionDraft {
  id: string;
  selected: string[];
  custom: string;
  customOpen: boolean;
}

export function toggleQuestion(draft: QuestionDraft, question: DshQuestion, label: string): QuestionDraft {
  if (!question.options.some((option) => option.label === label)) return draft;
  const selected = question.multiSelect ? (draft.selected.includes(label) ?
    draft.selected.filter((value: string) => value !== label) : draft.selected.concat(label)) : [label];
  return { id: draft.id, selected, custom: question.multiSelect ? draft.custom : '',
    customOpen: question.multiSelect ? draft.customOpen : false };
}

export function questionAnswers(request: DshQuestionRequest, drafts: QuestionDraft[]): DshQuestionAnswer[] | undefined {
  const answers: DshQuestionAnswer[] = [];
  for (const question of request.questions) {
    const draft = drafts.find((item) => item.id === question.id);
    if (!draft) return undefined;
    const selected = question.options.filter((option) => draft.selected.includes(option.label)).map((option) => option.label);
    const custom = draft.custom.trim();
    if ((!selected.length && !custom) || (!question.multiSelect && selected.length > 1)) return undefined;
    answers.push({ id: question.id, selected, custom: custom || undefined });
  }
  return answers.length ? answers : undefined;
}

// Route-scoped memory only: leaving a question card must not discard an unfinished answer.
export class QuestionDrafts {
  private values: Map<string, QuestionDraft[]> = new Map();

  read(request: DshQuestionRequest): QuestionDraft[] {
    const previous = this.values.get(`${request.sessionId}/${request.callId || request.id}`) || [];
    return request.questions.map((question): QuestionDraft => {
      const draft = previous.find((item) => item.id === question.id);
      return { id: question.id, selected: draft?.selected.slice() || [], custom: draft?.custom || '',
        customOpen: draft?.customOpen || question.options.length === 0 };
    });
  }

  save(request: DshQuestionRequest, drafts: QuestionDraft[]): void {
    this.values.set(`${request.sessionId}/${request.callId || request.id}`, drafts.map((draft): QuestionDraft => {
      return { id: draft.id, selected: draft.selected.slice(), custom: draft.custom, customOpen: draft.customOpen };
    }));
  }

  remove(request: DshQuestionRequest): void { this.values.delete(`${request.sessionId}/${request.callId || request.id}`); }
  clear(): void { this.values.clear(); }
}
