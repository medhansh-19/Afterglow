// One cancellable timer owns all transient feedback; older messages cannot clear newer ones.
export function createNotice({ show, schedule = setTimeout, cancel = clearTimeout, now = Date.now }) {
  let timer, remaining = 0, deadline = 0, paused = false, lastText = "", repeatAfter = 0;
  function clear() {
    cancel(timer);
    remaining = 0;
    show("");
  }
  function resume() {
    paused = false;
    cancel(timer);
    if (remaining > 0) {
      deadline = now() + remaining;
      timer = schedule(clear, remaining);
    }
  }
  return {
    show(text, duration = 5000) {
      if (text && text === lastText && now() < repeatAfter) return;
      lastText = text;
      repeatAfter = now() + 30000;
      cancel(timer);
      show(text);
      remaining = text ? duration : 0;
      if (!paused) resume();
    },
    clear,
    pause() {
      if (paused) return;
      paused = true;
      remaining = Math.max(0, deadline - now());
      cancel(timer);
    },
    resume,
  };
}
