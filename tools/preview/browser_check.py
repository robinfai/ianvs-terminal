"""Exercise the actual compiled Flutter showcase using Chromium accessibility."""
from pathlib import Path
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import shutil
import threading

from playwright.sync_api import sync_playwright, expect

root = Path(__file__).resolve().parents[2]
web = root / 'example/build/web'
output = root / 'build/foundation-browser'
output.mkdir(parents=True, exist_ok=True)
server = ThreadingHTTPServer(('127.0.0.1', 8765), partial(SimpleHTTPRequestHandler, directory=str(web)))
threading.Thread(target=server.serve_forever, daemon=True).start()
results = []


def reveal(page, locator):
    size = page.viewport_size
    page.mouse.move(size["width"] / 2, size["height"] / 2)
    for _ in range(16):
        if locator.count() and locator.first.is_visible():
            locator.first.scroll_into_view_if_needed()
            return locator.first
        page.mouse.wheel(0, 480)
        page.wait_for_timeout(160)
    raise AssertionError('Control did not enter the Flutter semantics viewport')


try:
    with sync_playwright() as p:
        executable = shutil.which('google-chrome') or shutil.which('chromium')
        if executable is None:
            raise RuntimeError('The CI runner has no installed Chrome/Chromium')
        browser = p.chromium.launch(executable_path=executable, headless=True, args=['--no-sandbox'])
        for name, size in [('desktop', {'width': 1280, 'height': 900}),
                           ('phone', {'width': 375, 'height': 812})]:
            page = browser.new_page(viewport=size, device_scale_factor=1)
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.on('console', lambda message: errors.append(message.text)
                    if message.type == 'error' else None)
            try:
                page.goto('http://127.0.0.1:8765', wait_until='networkidle')
                page.wait_for_selector('flutter-view', timeout=60000)
                placeholder = page.locator('flt-semantics-placeholder')
                if placeholder.count():
                    placeholder.evaluate('(element) => element.click()')
                page.wait_for_timeout(500)
                page.screenshot(path=str(output / f'{name}-light.png'))
                # Theme controls are real Material segmented buttons.
                page.get_by_role('button', name='Dark', exact=True).click()
                page.wait_for_timeout(250)
                page.screenshot(path=str(output / f'{name}-dark.png'))
                page.get_by_role('button', name='Light', exact=True).click()
                trigger = reveal(page, page.get_by_role('button', name='Session actions', exact=True))
                trigger.click()
                page.wait_for_timeout(250)
                if name == 'desktop':
                    # First root command is focused; Down selects the submenu.
                    page.keyboard.press('ArrowDown')
                    page.keyboard.press('ArrowRight')
                    expect(page.get_by_role('button', name='Side by side', exact=True)).to_be_visible()
                    page.screenshot(path=str(output / 'desktop-submenu.png'))
                    page.keyboard.press('Enter')
                    expect(page.get_by_role('button', name='Side by side', exact=True)).not_to_be_visible()
                    # Enter reopening the root proves focus returned to trigger.
                    page.keyboard.press('Enter')
                    expect(page.get_by_role('button', name='Split terminal', exact=True)).to_be_visible()
                    page.keyboard.press('Escape')
                    expect(page.get_by_role('button', name='Split terminal', exact=True)).not_to_be_visible()
                    edge = reveal(page, page.get_by_role('button', name='Edge test', exact=True))
                    edge.click()
                    page.get_by_role('button', name='Split terminal', exact=True).hover()
                    child = page.get_by_role('button', name='Side by side', exact=True)
                    expect(child).to_be_visible()
                    box = child.bounding_box()
                    assert box and 0 <= box['x'] and box['x'] + box['width'] <= size['width']
                    child.hover()
                    expect(child).to_be_visible()
                    page.screenshot(path=str(output / 'desktop-edge.png'))
                    page.mouse.click(5, 5)
                    expect(child).not_to_be_visible()
                else:
                    page.get_by_text('Split terminal', exact=True).click()
                    expect(page.get_by_text('Side by side', exact=True)).to_be_visible()
                    page.screenshot(path=str(output / 'phone-submenu.png'))
                    page.get_by_role('button', name='Back', exact=True).click()
                    expect(page.get_by_text('Pin session', exact=True)).to_be_visible()
                    page.get_by_text('Split terminal', exact=True).click()
                    page.keyboard.press('Escape')
                    expect(page.get_by_text('Pin session', exact=True)).to_be_visible()
                    page.get_by_role('button', name='Close', exact=True).click()
                    expect(page.get_by_text('Pin session', exact=True)).not_to_be_visible()
                confirm = reveal(page, page.get_by_role('button', name='Confirm close…', exact=True))
                confirm.click()
                expect(page.get_by_role('button', name='Keep session', exact=True)).to_be_visible()
                page.screenshot(path=str(output / f'{name}-confirmation.png'))
                page.keyboard.press('Enter')
                expect(page.get_by_role('button', name='Keep session', exact=True)).not_to_be_visible()
                assert not errors, errors
                results.append({'viewport': name, 'status': 'passed', 'errors': errors})
                print('BROWSER_PASSED', name, flush=True)
            except Exception as error:
                page.screenshot(path=str(output / f'{name}-failure.png'))
                (output / f'{name}-failure.html').write_text(page.content())
                print('BROWSER_FAILURE', name, str(error), flush=True)
                print('VISIBLE_SEMANTICS', page.locator('[role]').evaluate_all(
                    '(nodes) => nodes.slice(0, 80).map(n => ({role:n.getAttribute("role"), label:n.getAttribute("aria-label"), text:n.textContent}))'), flush=True)
                results.append({'viewport': name, 'status': 'failed', 'error': str(error), 'console': errors})
                raise
            finally:
                page.close()
        browser.close()
finally:
    server.shutdown()
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
