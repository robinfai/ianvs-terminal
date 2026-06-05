import "./index.css";
import { Composition } from "remotion";
import { InstantReplayDemo } from "./Composition";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="InstantReplayDemo"
        component={InstantReplayDemo}
        durationInFrames={750}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
