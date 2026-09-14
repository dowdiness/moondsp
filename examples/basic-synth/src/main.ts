import { createAudio } from "./audio";
import { readPage, createDomConnection, reportStartupFailure, type PageElements } from "./dom";
import { andThen, attempt, type Result } from "./result";
import { DEFAULT_SETTINGS } from "./synth";
import "./style.css";

function startApplication(elements: PageElements): Result<void> {
  return attempt(() => {
    const dom = createDomConnection(elements, DEFAULT_SETTINGS);
    const audio = createAudio(dom.view, dom.settings);
    dom.connect(audio);
    audio.initialize();
  });
}

// A failed acquisition skips every subsequent action, including audio creation.
const started = andThen(readPage(document), startApplication);
if (!started.ok) reportStartupFailure(document, started.error);
