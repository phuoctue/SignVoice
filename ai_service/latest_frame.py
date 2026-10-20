"""One waiting frame, independent of detector/LM inference time."""
import asyncio


class LatestFrameMailbox:
    def __init__(self):
        self.queue = asyncio.Queue(maxsize=1)
        self.dropped = 0

    def offer(self, packet):
        if self.queue.full():
            self.queue.get_nowait()
            self.dropped += 1
        self.queue.put_nowait(packet)

    async def get(self):
        return await self.queue.get()
