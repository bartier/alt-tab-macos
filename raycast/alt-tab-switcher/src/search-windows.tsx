import {
  Action,
  ActionPanel,
  closeMainWindow,
  getPreferenceValues,
  Icon,
  List,
  popToRoot,
  showToast,
  Toast,
} from "@raycast/api";
import { useExec } from "@raycast/utils";
import { execFile } from "child_process";
import { join } from "path";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

interface AltTabWindow {
  id: number;
  title: string;
  appName?: string;
  bundleId?: string;
  appPath?: string;
  spaceIndex?: number;
  isMinimized?: boolean;
  isHidden?: boolean;
  lastFocusOrder?: number;
}

interface Preferences {
  shortcutIndex: string;
  altTabPath: string;
}

const prefs = getPreferenceValues<Preferences>();
const binary = join(prefs.altTabPath || "/Applications/AltTab.app", "Contents/MacOS/AltTab");

async function focusWindow(window: AltTabWindow) {
  try {
    await closeMainWindow({ clearRootSearch: true });
    await execFileAsync(binary, [`--focus=${window.id}`]);
    await popToRoot();
  } catch (error) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Couldn't focus window",
      message: String(error),
    });
  }
}

export default function Command() {
  const { isLoading, data, error } = useExec(binary, [`--list=${prefs.shortcutIndex}`], {
    parseOutput: ({ stdout }) => JSON.parse(String(stdout)).windows as AltTabWindow[],
  });

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Search windows…">
      {error ? (
        <List.EmptyView
          icon={Icon.ExclamationMark}
          title="AltTab is not reachable"
          description={`Make sure AltTab is running and "Raycast integration" is enabled for Shortcut ${prefs.shortcutIndex} in AltTab Preferences → Controls.`}
        />
      ) : (
        (data ?? []).map((window) => (
          <List.Item
            key={window.id}
            title={window.title || window.appName || "Untitled"}
            subtitle={window.appName}
            icon={window.appPath ? { fileIcon: window.appPath } : Icon.AppWindow}
            keywords={window.appName ? [window.appName] : undefined}
            accessories={[
              ...(window.isMinimized ? [{ tag: "Minimized" }] : []),
              ...(window.isHidden ? [{ tag: "Hidden" }] : []),
              ...(window.spaceIndex !== undefined ? [{ text: `Space ${window.spaceIndex}` }] : []),
            ]}
            actions={
              <ActionPanel>
                <Action title="Focus Window" icon={Icon.AppWindow} onAction={() => focusWindow(window)} />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}
